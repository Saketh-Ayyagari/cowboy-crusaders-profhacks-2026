"""
Webcam → MediaPipe Face Mesh → 2D pixel position of the forehead landmark.
"""
import numpy as np
import cv2 as cv
import matplotlib.pyplot as plt
import mediapipe as mp
import opencv_utils as cv_utils

from mediapipe.tasks import python
from mediapipe.tasks.python import vision
from mediapipe.tasks.python.vision import drawing_utils
from mediapipe.tasks.python.vision import drawing_styles

##################################################################
# CONSTANTS (May need to update depending on the machine)
##################################################################
# Center forehead (glabella) in MediaPipe Face Mesh (468 landmarks).
FOREHEAD_LANDMARK_INDEX = 10 
FACE_LANDMARKER_V2_PATH = "PersonalProjects/ProfHacks2026/face_landmarker_v2_with_blendshapes.task" # can be updated if desired

'''
Draws specific facial landmarks onto an RGB image. 
'''
def draw_landmarks_on_image(rgb_image, detection_result):
  face_landmarks_list = detection_result.face_landmarks
  annotated_image = np.copy(rgb_image)

  # Loop through the detected faces to visualize.
  for idx in range(len(face_landmarks_list)):
    face_landmarks = face_landmarks_list[idx]

    # Draw the face landmarks.
    drawing_utils.draw_landmarks(
        image=annotated_image,
        landmark_list=face_landmarks,
        connections=vision.FaceLandmarksConnections.FACE_LANDMARKS_TESSELATION,
        landmark_drawing_spec=None,
        connection_drawing_spec=drawing_styles.get_default_face_mesh_tesselation_style())
    drawing_utils.draw_landmarks(
        image=annotated_image,
        landmark_list=face_landmarks,
        connections=vision.FaceLandmarksConnections.FACE_LANDMARKS_CONTOURS,
        landmark_drawing_spec=None,
        connection_drawing_spec=drawing_styles.get_default_face_mesh_contours_style())
    drawing_utils.draw_landmarks(
        image=annotated_image,
        landmark_list=face_landmarks,
        connections=vision.FaceLandmarksConnections.FACE_LANDMARKS_LEFT_IRIS,
          landmark_drawing_spec=None,
          connection_drawing_spec=drawing_styles.get_default_face_mesh_iris_connections_style())
    drawing_utils.draw_landmarks(
        image=annotated_image,
        landmark_list=face_landmarks,
        connections=vision.FaceLandmarksConnections.FACE_LANDMARKS_RIGHT_IRIS,
        landmark_drawing_spec=None,
        connection_drawing_spec=drawing_styles.get_default_face_mesh_iris_connections_style())

  return annotated_image
'''
Given the "results" after model detection, return the (x, y) coordinates of the point on the forehead
'''
def get_forehead_point(result, image_width, image_height):
    """
    Given the results from FaceLandmarker.detect(), return the (x, y)
    pixel coordinates of the forehead point (landmark #10).
    
    Landmark 10 is the standard forehead/top-of-face point in MediaPipe's
    468-point face mesh map.
    """
    if not result.face_landmarks:
        return None  # no face detected

    # Get the first detected face's landmarks
    face_landmarks = result.face_landmarks[0]

    # Landmark #10 = forehead center
    forehead = face_landmarks[FOREHEAD_LANDMARK_INDEX]

    # Landmarks are normalized (0.0 - 1.0), so convert to pixel coords
    x = int(forehead.x * image_width)
    y = int(forehead.y * image_height)

    return (x, y)


def main() -> None:
    # initializing camera
    CAMERA_INDEX = 0
    camera = cv.VideoCapture(CAMERA_INDEX)
    while True:
        # getting image
        hasFrame, frame = camera.read()
        # Create an FaceLandmarker object and detector.
        base_options = python.BaseOptions(model_asset_path=FACE_LANDMARKER_V2_PATH)
        options = vision.FaceLandmarkerOptions(base_options=base_options,
                                            output_face_blendshapes=True,
                                            output_facial_transformation_matrixes=True,
                                            num_faces=1)
        detector = vision.FaceLandmarker.create_from_options(options)

        if hasFrame: # only annotates image if camera frame is received. 
            # convert frame (numpy 2d array) to mediapipe.Image class
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame)

            # passing image into detector
            detection_result = detector.detect(image)

            # Process the detection result. In this case, visualize it.
            annotated_image = np.copy(frame)  
            # get forehead point given results
            forehead_point = get_forehead_point(
                result=detection_result,
                image_width=frame.shape[1],
                image_height=frame.shape[0]
            )
            # does not display dot if shown
            if forehead_point is not None:
                cv.circle(annotated_image, forehead_point, 5, (0, 0, 255), -1)
            
            annotated_image = np.flip(annotated_image, 1) # flips image for output display
            
            
            cv_utils.show_image(annotated_image) # can be removed if necessary. 


        
if __name__ == "__main__":
    main()
