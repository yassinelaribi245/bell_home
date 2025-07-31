<?php

namespace App\Http\Controllers\Api;
use App\Models\Camera;
use App\Models\Home;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class cameraController extends Controller
{
    public function index()
    {
        return camera::all();
    }
public function getUserByCameraCode(Request $request)
    {
        $request->validate([
            'camera_code' => 'required|string',
        ]);

        $cameraCode = $request->input('camera_code');

        // Find the camera
        $camera = Camera::where('cam_code', $cameraCode)->first();

        if (!$camera) {
            return response()->json(['error' => 'Camera not found'], 404);
        }

        // Get home associated with camera
        $home = $camera->home;

        if (!$home) {
            return response()->json(['error' => 'Home not found'], 404);
        }

        // Find user who owns the home
        $user = User::find($home->id_user);

        if (!$user) {
            return response()->json(['error' => 'User not found'], 404);
        }

        if (!$user->fcm) {
            return response()->json(['error' => 'User not logged in'], 403);
        }

        return response()->json([
            'user' => [
                'email' => $user->email,
                'fcm' => $user->fcm,
            ]
        ]);
    }
    public function cameras_user(Request $request)
{
    $request->validate([
        'email' => 'required|email',
    ]);

    // Get the user by email
    $user = User::where('email', $request->input('email'))->first();

    if (!$user) {
        return response()->json(['error' => 'User not found'], 404);
    }

    // Get all homes owned by the user (you must define a homes() relationship in User model)
    $homes = $user->homes;

    if ($homes->isEmpty()) {
        return response()->json(['error' => 'No homes found for user'], 404);
    }

    // Collect all cameras from all homes (assuming each Home has a cameras() relationship)
    $cameras = collect();

    foreach ($homes as $home) {
        $cameras = $cameras->merge($home->cameras);
    }

    // Return the list of cameras
    return response()->json([
        'user_email' => $user->email,
        'camera_count' => $cameras->count(),
        'cameras' => $cameras,
    ]);
}

    /**
     * Show the form for creating a new resource.
     */
    public function create()
    {

    }

    /**
     * Store a newly created resource in storage.
     */
    public function store(Request $request)
    {
        //
    }

    /**
     * Display the specified resource.
     */
    public function show(string $id)
    {
        //
    }

    /**
     * Show the form for editing the specified resource.
     */
    public function edit(string $id)
    {
        //
    }

    /**
     * Update the specified resource in storage.
     */
    public function update(Request $request, string $id)
    {
        //
    }

    /**
     * Remove the specified resource from storage.
     */
    public function destroy(string $id)
    {
        $camera = Camera::find($id);
        if ($camera) {
            $camera->delete();
            return response()->json(['message' => 'Camera deleted successfully']);
        }
        return response()->json(['error' => 'Camera not found'], 404);
    }

    // NEW: Update camera status when testing app connects/disconnects
    public function updateCameraStatus(Request $request)
    {
        $request->validate([
            'camera_code' => 'required|string',
            'is_online' => 'required|boolean',
            'is_active' => 'boolean',
            'status' => 'string',
            'timestamp' => 'string',
        ]);

        try {
            $camera = Camera::where('cam_code', $request->input('camera_code'))->first();

            if (!$camera) {
                return response()->json(['error' => 'Camera not found'], 404);
            }

            $camera->update([
                'is_online' => $request->input('is_online'),
                'is_active' => $request->input('is_active', $camera->is_active),
                'health_status' => $request->input('status', $camera->health_status),
                'updated_at' => now(),
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Camera status updated successfully',
                'camera' => $camera,
            ]);

        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Failed to update camera status',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // NEW: Handle camera connection event
    public function cameraConnected(Request $request)
    {
        $request->validate([
            'camera_code' => 'required|string',
            'timestamp' => 'string',
        ]);

        try {
            $camera = Camera::where('cam_code', $request->input('camera_code'))->first();

            if (!$camera) {
                return response()->json(['error' => 'Camera not found'], 404);
            }

            $camera->update([
                'is_online' => true,
                'health_status' => 'online',
                'updated_at' => now(),
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Camera marked as connected',
                'camera' => $camera,
            ]);

        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Failed to update camera connection status',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // NEW: Handle camera disconnection event
    public function cameraDisconnected(Request $request)
    {
        $request->validate([
            'camera_code' => 'required|string',
            'timestamp' => 'string',
        ]);

        try {
            $camera = Camera::where('cam_code', $request->input('camera_code'))->first();

            if (!$camera) {
                return response()->json(['error' => 'Camera not found'], 404);
            }

            $camera->update([
                'is_online' => false,
                'health_status' => 'offline',
                'updated_at' => now(),
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Camera marked as disconnected',
                'camera' => $camera,
            ]);

        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Failed to update camera disconnection status',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    // NEW: Handle comprehensive camera status update
    public function cameraStatusUpdate(Request $request)
    {
        $request->validate([
            'camera_code' => 'required|string',
            'is_online' => 'required|boolean',
            'is_camera_on' => 'boolean',
            'status' => 'string',
            'timestamp' => 'string',
        ]);

        try {
            \Log::info('Camera status update received', $request->all());
            
            $camera = Camera::where('cam_code', $request->input('camera_code'))->first();

            if (!$camera) {
                \Log::warning('Camera not found in database', ['camera_code' => $request->input('camera_code')]);
                return response()->json(['error' => 'Camera not found'], 404);
            }

            $oldStatus = [
                'is_online' => $camera->is_online,
                'is_active' => $camera->is_active,
                'health_status' => $camera->health_status,
            ];

            $camera->update([
                'is_online' => $request->input('is_online'),
                'is_active' => $request->input('is_camera_on', $camera->is_active),
                'health_status' => $request->input('status', $camera->health_status),
                'updated_at' => now(),
            ]);

            \Log::info('Camera status updated successfully', [
                'camera_code' => $request->input('camera_code'),
                'old_status' => $oldStatus,
                'new_status' => [
                    'is_online' => $camera->is_online,
                    'is_active' => $camera->is_active,
                    'health_status' => $camera->health_status,
                ]
            ]);

            return response()->json([
                'success' => true,
                'message' => 'Camera status updated successfully',
                'camera' => $camera,
            ]);

        } catch (\Exception $e) {
            \Log::error('Failed to update camera status', [
                'camera_code' => $request->input('camera_code'),
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            
            return response()->json([
                'error' => 'Failed to update camera status',
                'message' => $e->getMessage()
            ], 500);
        }
    }
}
