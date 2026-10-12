import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import numpy as np

spec = importlib.util.spec_from_file_location('quality',Path(__file__).resolve().parents[1]/'reconstruction-quality.py')
quality = importlib.util.module_from_spec(spec)
spec.loader.exec_module(quality)


class IndependentQualityTests(unittest.TestCase):
    def test_similarity_recovers_known_transform_without_mesh_fitting(self):
        source = np.random.default_rng(29).normal(size=(12,3))
        rotation = np.array([[0,-1,0],[1,0,0],[0,0,1]])
        target = 2.5 * source @ rotation.T + [8,-3,2]
        alignment = quality.similarity(source,target)
        np.testing.assert_allclose(quality.transform(source,alignment),target,atol=1e-12)
        self.assertAlmostEqual(alignment[0],2.5)
        self.assertAlmostEqual(np.linalg.det(alignment[1]),1)

    def test_degenerate_and_nonfinite_centres_refused(self):
        for source in [np.zeros((6,3)), np.full((6,3),np.nan), np.zeros((5,3))]:
            with self.assertRaises(ValueError): quality.similarity(source,source)

    def test_known_pose_rotation_and_one_displaced_camera_are_detected(self):
        positions = np.random.default_rng(9).normal(size=(12,3))
        truth = {'cameras':[{'preparedFile':f'{i}.jpg','position':p.tolist(),'rotation':np.eye(3).tolist()} for i,p in enumerate(positions)]}
        cameras = [{'img_name':f'{i}.jpg','position':p.tolist(),'rotation':np.eye(3).tolist()} for i,p in enumerate(positions)]
        self.assertLess(quality.evaluate(truth,cameras)['cameraPositionRMSE'],1e-12)
        cameras[0]['position'][0] += .5
        self.assertGreater(quality.evaluate(truth,cameras)['cameraPositionRMSE'],.1)
        self.assertAlmostEqual(quality.rotation_error(np.diag([-1,-1,1]),np.eye(3)),180)

    def test_visible_face_grid_detects_missing_side_and_distorted_vertices(self):
        points = []
        for axis,sign in [(0,-1),(0,1),(1,1),(2,-1),(2,1)]:
            for a in np.linspace(-.8,.8,9):
                for b in np.linspace(-.8,.8,9):
                    point = [0,0,0]; point[axis]=sign
                    other=[i for i in range(3) if i!=axis]; point[other[0]]=a;point[other[1]]=b
                    points.append(point)
        exact = quality.cube_metrics(points)
        self.assertTrue(exact['valid'])
        self.assertEqual(exact['vertexAbsoluteDistanceP95'],0)
        self.assertTrue(all(v==1 for v in exact['visibleFaceGridCoverageWithin0_15'].values()))
        missing = quality.cube_metrics(np.asarray(points)[np.asarray(points)[:,0]!=1])
        self.assertLess(missing['visibleFaceGridCoverageWithin0_15']['right'],.3)
        distorted = quality.cube_metrics(np.asarray(points)*.9)
        self.assertGreater(distorted['vertexAbsoluteDistanceMedian'],.09)

    def test_wrong_location_mesh_retains_camera_report_and_rejects_quality(self):
        positions = np.random.default_rng(91).normal(size=(12,3))
        truth = {'cameras':[{'preparedFile':f'{i}.jpg','position':p.tolist(),'rotation':np.eye(3).tolist()} for i,p in enumerate(positions)]}
        cameras = [{'img_name':f'{i}.jpg','position':p.tolist(),'rotation':np.eye(3).tolist()} for i,p in enumerate(positions)]
        points = np.random.default_rng(22).normal(size=(80,3)) + [30,30,30]
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            mesh = folder/'wrong.ply'
            mesh.write_text('ply\nformat ascii 1.0\nelement vertex 80\nproperty float x\nproperty float y\nproperty float z\nend_header\n'+'\n'.join(' '.join(map(str,p)) for p in points))
            result = quality.evaluate(truth,cameras,mesh)
            self.assertLess(result['cameraPositionRMSE'],1e-12)
            self.assertFalse(result['qualityAccepted'])
            self.assertFalse(result['mesh']['valid'])
            self.assertEqual(result['mesh']['reason'],'too-few-cube-region-vertices')
            self.assertEqual(result['mesh']['sampledVertices'],80)
            self.assertEqual(result['mesh']['cubeRegionVertices'],0)
            self.assertEqual(result['mesh']['outsideCubeRegionFraction'],1)
            self.assertIsNone(result['mesh']['vertexAbsoluteDistanceMedian'])
            self.assertIsNone(result['mesh']['vertexAbsoluteDistanceP95'])
            self.assertTrue(all(value==0 for value in result['mesh']['visibleFaceGridCoverageWithin0_15'].values()))
            json.dumps(result,allow_nan=False)
            (folder/'truth.json').write_text(json.dumps(truth))
            (folder/'cameras.json').write_text(json.dumps(cameras))
            command = [sys.executable,str(Path(__file__).resolve().parents[1]/'reconstruction-quality.py'),'--truth',str(folder/'truth.json'),'--cameras',str(folder/'cameras.json'),'--mesh',str(mesh),'--output',str(folder/'report.json')]
            for flag,expected in [([],0),(['--require-quality'],2)]:
                completed = subprocess.run(command+flag,capture_output=True,text=True)
                self.assertEqual(completed.returncode,expected,completed.stderr)
                self.assertFalse(json.loads((folder/'report.json').read_text())['qualityAccepted'])

    def test_criteria_are_reported_and_bad_camera_geometry_cannot_pass(self):
        positions = np.random.default_rng(9).normal(size=(12,3))
        truth = {'cameras':[{'preparedFile':f'{i}.jpg','position':p.tolist(),'rotation':np.eye(3).tolist()} for i,p in enumerate(positions)]}
        cameras = [{'img_name':f'{i}.jpg','position':p.tolist(),'rotation':np.eye(3).tolist()} for i,p in enumerate(positions)]
        self.assertTrue(quality.evaluate(truth,cameras)['qualityAccepted'])
        cameras[0]['position'][0] += 4
        report = quality.evaluate(truth,cameras)
        self.assertFalse(report['qualityAccepted'])
        self.assertIn('camera-position-rmse-exceeds-limit',report['qualityAssessment']['failures'])
        self.assertEqual(report['qualityAssessment']['criteria']['maxCameraPositionRMSE'],.15)
        with self.assertRaises(ValueError): quality.evaluate(truth,cameras,criteria={'maxCameraPositionRMSE':float('nan')})
        with self.assertRaises(ValueError): quality.evaluate(truth,cameras,criteria={'unknown':1})


if __name__ == '__main__': unittest.main()
