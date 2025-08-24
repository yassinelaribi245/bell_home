<?php

namespace App\Http\Controllers\Api;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class VisitorController extends Controller
{
    public function store(Request $request)
    {
        // 1. Validate the request for 'camera_code'
        $validated = $request->validate([
            'camera_code' => 'required|string|alpha_num|max:255',
            'frames' => 'required|array',
            'frames.*' => 'required|image|mimes:png,jpg,jpeg|max:5120',
        ]);

        $cameraCode = $validated['camera_code'];
        $files = $validated['frames'];

        // 2. Define the camera-specific folder path within the 'public' disk
        // e.g., 'visitors/front_door_cam_01'
        $cameraFolderPath = 'visitors/' . $cameraCode;

        // 3. --- NEW: DELETE OLD PHOTOS ---
        // Before saving new files, delete the entire directory for this camera code.
        // This is much faster than deleting files one by one.
        // The 'public' disk corresponds to 'storage/app/public'.
        if (Storage::disk('public')->exists($cameraFolderPath)) {
            Storage::disk('public')->deleteDirectory($cameraFolderPath);
            Log::info("Deleted old directory: " . $cameraFolderPath);
        }

        // 4. Loop through each new file and store it
        $paths = [];
        foreach ($files as $file) {
            $filename = Str::uuid() . '.' . $file->getClientOriginalExtension();

            try {
                // Store the file in the now-empty or brand-new directory
                $path = $file->storeAs($cameraFolderPath, $filename, 'public');
                $url = Storage::url($path);
                $paths[] = $url;

            } catch (\Exception $e) {
                Log::error('File storage failed for camera ' . $cameraCode . ': ' . $e->getMessage());
            }
        }

        // 5. Return the response
        if (empty($paths)) {
            return response()->json([
                'message' => 'Request processed, but no new files were saved. Check server logs.',
            ], 500);
        }

        return response()->json([
            'message' => count($paths) . ' new frames saved for camera ' . $cameraCode . '. Old photos deleted.',
            'paths' => $paths,
        ]);
    }
}
