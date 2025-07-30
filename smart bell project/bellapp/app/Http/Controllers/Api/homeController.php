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

        $homes = $user->homes;

        if ($homes->isEmpty()) {
            return response()->json(['message' => 'No homes found for this user'], 200);
        }

        return response()->json([
            'user_email' => $user->email,
            'home_count' => $homes->count(),
            'homes' => $homes,
        ]);
    }
}

