import sys
import os

# Absolute path to the models folder
models_path = r"C:\Users\larib\AppData\Roaming\Python\Python313\site-packages\face_recognition_models\models"

# Make sure the folder is in sys.path
if models_path not in sys.path:
    sys.path.append(models_path)

# Also set the environment variable so face_recognition can find the models
os.environ['FACE_RECOGNITION_MODEL_PATH'] = models_path
from flask import Flask, request, jsonify
import face_recognition
import time

app = Flask(__name__)

def load_specific_known_faces(base_library_path, allowed_ids):
    print(f"\nScanning library at: {base_library_path}")
    print(f"Restricted to IDs: {allowed_ids}")
    start_time = time.time()
    
    known_face_encodings = []
    known_face_names = []

    if not os.path.isdir(base_library_path):
        print(f"Warning: Base library path {base_library_path} does not exist.")
        return [], []
    for person_id in allowed_ids:
        person_folder = os.path.join(base_library_path, str(person_id)) # Ensure ID is a string for path joining
        
        if os.path.isdir(person_folder):
            print(f"  - Loading faces for allowed person_id: {person_id}")
            for filename in os.listdir(person_folder):
                if filename.endswith((".jpg", ".png", ".jpeg")):
                    image_path = os.path.join(person_folder, filename)
                    image = face_recognition.load_image_file(image_path)
                    encodings = face_recognition.face_encodings(image)
                    
                    if encodings:
                        known_face_encodings.append(encodings[0])
                        known_face_names.append(person_id)
        else:
            print(f"  - Skipping ID {person_id}: directory not found.")
            
    end_time = time.time()
    print(f"Finished loading {len(known_face_names)} samples from {len(allowed_ids)} allowed IDs in {end_time - start_time:.2f} seconds.")
    return known_face_encodings, known_face_names

@app.route('/identify_secure', methods=['POST'])
def identify_person_secure():
    data = request.get_json()
    if not data or 'new_images_path' not in data or 'known_visitors_path' not in data or 'allowed_visitor_ids' not in data:
        return jsonify({"error": "Missing required parameters"}), 400

    new_images_path = data['new_images_path']
    known_visitors_path = data['known_visitors_path']
    allowed_visitor_ids = data['allowed_visitor_ids']

    if not isinstance(allowed_visitor_ids, list):
         return jsonify({"error": "'allowed_visitor_ids' must be a list"}), 400

    print(f"\n--- New Secure Identification Request ---")
    print(f"Analyzing new images from: {new_images_path}")

    known_face_encodings, known_face_names = load_specific_known_faces(known_visitors_path, allowed_visitor_ids)

    if not known_face_encodings:
        return jsonify({"status": "complete", "identification": "Unknown", "reason": "No valid faces found for the provided visitor IDs."})

    for filename in os.listdir(new_images_path):
        if filename.endswith((".jpg", ".png", ".jpeg")):
            image_path = os.path.join(new_images_path, filename)
            print(f"  -> Checking {filename}...")
            unknown_image = face_recognition.load_image_file(image_path)
            unknown_encodings = face_recognition.face_encodings(unknown_image)

            if unknown_encodings:
                matches = face_recognition.compare_faces(known_face_encodings, unknown_encodings[0], tolerance=0.6)
                if True in matches:
                    first_match_index = matches.index(True)
                    identified_person_id = known_face_names[first_match_index]
                    print(f"  SUCCESS! Identified as: {identified_person_id}")
                    print(jsonify({"status": "complete", "identification": identified_person_id}))
                    return jsonify({"status": "complete", "identification": identified_person_id})

    print("  No match found in any of the new images.")
    return jsonify({"status": "complete", "identification": "Unknown"})


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=True)
