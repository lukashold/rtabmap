"""Independent synthetic quality evaluation, never an input to the engines.

Fit the unavoidable SfM similarity using CAMERA CENTRES only. Do not fit a cube
to the mesh: doing so would conceal shape errors. Units refer to the synthetic
scene (cube side 2), not measured metres or real iPhone accuracy.
"""
import argparse
import json
import math
from pathlib import Path
import numpy as np


def similarity(source, target):
    a, b = np.asarray(source, dtype=float), np.asarray(target, dtype=float)
    if a.shape != b.shape or a.ndim != 2 or a.shape[1] != 3 or len(a) < 6:
        raise ValueError('At least six corresponding camera centres are required')
    if not np.isfinite(a).all() or not np.isfinite(b).all():
        raise ValueError('Non-finite camera centres')
    ac, bc = a-a.mean(0), b-b.mean(0)
    if np.linalg.matrix_rank(ac) < 2 or np.linalg.matrix_rank(bc) < 2:
        raise ValueError('Camera centres cannot determine an alignment')
    u, singular, vt = np.linalg.svd(bc.T @ ac / len(a))
    signs = np.ones(3)
    if np.linalg.det(u @ vt) < 0:
        signs[-1] = -1
    rotation = u @ np.diag(signs) @ vt
    scale = float((singular * signs).sum() / (ac * ac).sum() * len(a))
    if not math.isfinite(scale) or scale <= 0:
        raise ValueError('Invalid similarity scale')
    offset = b.mean(0) - scale * (rotation @ a.mean(0))
    return scale, rotation, offset


def transform(points, alignment):
    scale, rotation, offset = alignment
    return scale * (np.asarray(points) @ rotation.T) + offset


def rotation_error(estimated, truth):
    delta = np.asarray(estimated) @ np.asarray(truth).T
    return math.degrees(math.acos(float(np.clip((np.trace(delta)-1)/2, -1, 1))))


def ply_vertices(path, limit=200_000):
    """Read scalar PLY vertices only, sampling uniformly by row, never by position."""
    types = {'float':'f4','float32':'f4','double':'f8','float64':'f8',
             'uchar':'u1','uint8':'u1','char':'i1','int8':'i1',
             'ushort':'u2','uint16':'u2','short':'i2','int16':'i2',
             'uint':'u4','uint32':'u4','int':'i4','int32':'i4'}
    with open(path, 'rb') as stream:
        properties, count, encoding, element, total = [], 0, None, None, 0
        while True:
            line = stream.readline(4096)
            total += len(line)
            if not line or total > 65536:
                raise ValueError('Invalid PLY header')
            fields = line.decode('ascii').split()
            if fields[:1] == ['format']:
                encoding = fields[1]
            elif fields[:1] == ['element']:
                element = fields[1]
                if element == 'vertex':
                    count = int(fields[2])
            elif fields[:1] == ['property'] and element == 'vertex':
                if len(fields) != 3 or fields[1] not in types:
                    raise ValueError('Unsupported vertex property')
                properties.append((fields[2],types[fields[1]]))
            elif fields == ['end_header']:
                break
        if not 1 <= count <= 10_000_000 or not {'x','y','z'}.issubset(dict(properties)):
            raise ValueError('Invalid PLY vertices')
        step = max(1, math.ceil(count / limit))
        if encoding == 'ascii':
            indices = [list(dict(properties)).index(axis) for axis in ('x','y','z')]
            points = []
            for index in range(count):
                line = stream.readline(16384).split()
                if len(line) != len(properties):
                    raise ValueError('Truncated PLY')
                if index % step == 0:
                    points.append([float(line[i]) for i in indices])
            result = np.asarray(points)
        elif encoding in ('binary_little_endian','binary_big_endian'):
            endian = '<' if encoding == 'binary_little_endian' else '>'
            dtype = np.dtype([(name,endian+kind) for name,kind in properties])
            # File mapping avoids loading huge original models or face arrays.
            data = np.memmap(path, dtype=dtype, mode='r', offset=stream.tell(), shape=(count,))
            result = np.column_stack([data[axis][::step] for axis in ('x','y','z')]).astype(float)
        else:
            raise ValueError('Unsupported PLY encoding')
    if not np.isfinite(result).all():
        raise ValueError('Non-finite mesh coordinates')
    return result


def cube_metrics(points):
    """Vertex-to-cube distance in a fixed ROI; also report points outside it.

    Bottom face is unobserved in this capture and excluded from coverage.
    Vertex sampling depends on tessellation; this is not surface Chamfer error.
    """
    points = np.asarray(points)
    region = (np.abs(points[:,[0,2]]) <= 1.3).all(1) & (points[:,1] >= -.99) & (points[:,1] <= 1.3)
    selected = points[region]
    if len(selected) < 10:
        raise ValueError('Too few mesh vertices in the fixed cube region')
    q = np.abs(selected) - 1
    distance = np.linalg.norm(np.maximum(q,0),axis=1) + np.minimum(q.max(1),0)
    distance = np.abs(distance)
    # Fixed sample grid on the FIVE visible faces, no alignment to the mesh.
    face_coverage = {}
    grid = np.linspace(-.8,.8,9)
    for axis, sign, name in [(0,-1,'left'),(0,1,'right'),(1,1,'top'),(2,-1,'back'),(2,1,'front')]:
        samples = []
        for first in grid:
            for second in grid:
                sample = [0.,0.,0.]; sample[axis] = sign
                other = [i for i in range(3) if i != axis]
                sample[other[0]], sample[other[1]] = first, second
                samples.append(sample)
        nearest = []
        for sample in samples:
            nearest.append(float(np.linalg.norm(selected-np.asarray(sample),axis=1).min()))
        face_coverage[name] = float((np.asarray(nearest) <= .15).mean())
    return {'sampledVertices':len(points),'cubeRegionVertices':len(selected),
            'outsideCubeRegionFraction':float(1-region.mean()),
            'vertexAbsoluteDistanceMedian':float(np.median(distance)),
            'vertexAbsoluteDistanceP95':float(np.quantile(distance,.95)),
            'vertexDistanceUnder0_05Fraction':float((distance <= .05).mean()),
            'visibleFaceGridCoverageWithin0_15':face_coverage,
            'method':'Camera-aligned vertex distances; fixed ROI; 9×9 samples per visible face. Bottom/floor excluded; no surface-area weighting.'}


def evaluate(truth, cameras, mesh=None, convention='right-down-forward'):
    reference = {item['preparedFile']:item for item in truth['cameras']}
    pairs = [(item,reference[item['img_name']]) for item in cameras if item.get('img_name') in reference]
    if len({item[0]['img_name'] for item in pairs}) != len(pairs):
        raise ValueError('Duplicate camera names')
    alignment = similarity([a['position'] for a,b in pairs], [b['position'] for a,b in pairs])
    residual = np.linalg.norm(transform([a['position'] for a,b in pairs],alignment)-[b['position'] for a,b in pairs],axis=1)
    errors = []
    for a,b in pairs:
        rotation = np.asarray(a['rotation'])
        if convention == 'right-up-back':
            rotation = rotation @ np.diag([1,-1,-1])
        errors.append(rotation_error(alignment[1] @ rotation,b['rotation']))
    result = {'format':'kantura-synthetic-quality','version':1,
              'fieldAccuracyValidated':False,'polycamComparisonPerformed':False,
              'units':'Synthetic scene units: cube side 2; arbitrary SfM scale aligned using camera centres only.',
              'registeredCameras':len(pairs),'expectedCameras':len(reference),
              'cameraPositionRMSE':float(np.sqrt((residual**2).mean())),
              'cameraPositionP95':float(np.quantile(residual,.95)),
              'cameraRotationMedianDegrees':float(np.median(errors)),
              'cameraRotationP95Degrees':float(np.quantile(errors,.95)),
              'alignment':{'scale':alignment[0],'rotation':alignment[1].tolist(),'translation':alignment[2].tolist()}}
    if mesh:
        result['mesh'] = cube_metrics(transform(ply_vertices(mesh),alignment))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--truth',type=Path,required=True)
    parser.add_argument('--cameras',type=Path,required=True)
    parser.add_argument('--mesh',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--convention',choices=['right-down-forward','right-up-back'],default='right-down-forward')
    args = parser.parse_args()
    result = evaluate(json.loads(args.truth.read_text('utf8')),json.loads(args.cameras.read_text('utf8')),args.mesh,args.convention)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False),'utf8')
    print(json.dumps({key:value for key,value in result.items() if key != 'alignment'},indent=2))


if __name__ == '__main__':
    main()
