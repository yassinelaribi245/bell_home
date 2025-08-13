<?php

namespace App\Http\Controllers\Api;

use App\Models\Camera;
use App\Models\Home;
use App\Models\User;
use Illuminate\Http\Request;

class HomeController extends Controller
{
    
    public function getHomesByEmail(Request $request)
    {
        $request->validate([
            'email' => 'required|email',
        ]);

        $user = User::where('email', $request->email)->first();

        if (!$user) {
            return response()->json(['error' => 'User not found'], 404);
        }

        $homes = Home::where('id_user', $user->id)->get();

        if ($homes->isEmpty()) {
            return response()->json(['message' => 'No homes found for this user'], 200);
        }

        return response()->json([
            'user_email' => $user->email,
            'home_count' => $homes->count(),
            'homes' => $homes,
        ]);
    }
    public function getCamerasByHomeId($homeid)
    {
        $cameras = Camera::where('id_home', $homeid)->get();

        if ($cameras->isEmpty()) {
            return response()->json(['message' => 'No cameras found for this home'], 200);
        }

        return response()->json([
            'home_id' => $homeid,
            'cameras' => $cameras,
        ]);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'superficie' => 'required|numeric|min:1',
            'longitude' => 'required|numeric',
            'latitude' => 'required|numeric',
            'num_cam' => 'sometimes|nullable|integer|min:0',
            'email' => 'required|exists:users,email'
        ]);

        $user = User::where('email', $validated['email'])->first();

        if (!$user) {
            return response()->json([
                'success' => false,
                'message' => 'User not found',
            ], 404);
        }

        unset($validated['email']);

        // Assign default 0 if num_cam is not provided or null
        if (!isset($validated['num_cam'])) {
            $validated['num_cam'] = 0;
        }

        $validated['id_user'] = $user->id;

        $home = Home::create($validated);

        return response()->json([
            'success' => true,
            'message' => 'Home created successfully',
            'home' => $home
        ], 201);
    }
    public function destroy(string $homeid)
    {
        $home = Home::find($homeid);
        if ($home) {
            $home->delete();
            Camera::where('id_home', $homeid)->delete();
            return response()->json(['message' => 'Home deleted successfully']);
        }

        return response()->json(['error' => 'Home not found'], 404);
    }

}

