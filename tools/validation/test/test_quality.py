import importlib.util
from pathlib import Path
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
        self.assertEqual(exact['vertexAbsoluteDistanceP95'],0)
        self.assertTrue(all(v==1 for v in exact['visibleFaceGridCoverageWithin0_15'].values()))
        missing = quality.cube_metrics(np.asarray(points)[np.asarray(points)[:,0]!=1])
        self.assertLess(missing['visibleFaceGridCoverageWithin0_15']['right'],.3)
        distorted = quality.cube_metrics(np.asarray(points)*.9)
        self.assertGreater(distorted['vertexAbsoluteDistanceMedian'],.09)


if __name__ == '__main__': unittest.main()
