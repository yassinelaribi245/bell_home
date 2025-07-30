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
        //
    }
}
