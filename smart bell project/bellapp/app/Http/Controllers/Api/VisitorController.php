<?php

namespace App\Http\Controllers\Api;
use Illuminate\Support\Facades\Http;
use App\Models\User;
use App\Models\visiteur;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
// We no longer need Carbon or Str for this naming scheme
// use Illuminate\Support\Str;
// use Carbon\Carbon;

class VisitorController extends Controller
{
    public function store(Request $request)
    {
        $validated = $request->validate([
            'camera_code' => 'required|string|alpha_num|max:255',
            'frames' => 'required|array',
            'frames.*' => 'required|image|mimes:png,jpg,jpeg|max:5120',
        ]);

        $cameraCode = $validated['camera_code'];
        $files = $validated['frames'];


        // Get the user linked to this camera
        $user = User::select('users.id as user_id')
            ->join('homes', 'users.id', '=', 'homes.id_user')
            ->join('camera', 'homes.id', '=', 'camera.id_home')
            ->where('camera.cam_code', $cameraCode)
            ->first();
        $cameraFolderPath = 'visitors/' . $cameraCode;
        if (!$user) {
            return response()->json(['message' => 'Camera not linked to a user'], 404);
        }

        $allowedVisitorIds = DB::table('visiteur')
            ->select('visiteur.id')
            ->join('camera_visiteur', 'visiteur.id', '=', 'camera_visiteur.id_visiteur')
            ->join('camera', 'camera_visiteur.id_camera', '=', 'camera.id')
            ->join('homes', 'camera.id_home', '=', 'homes.id')
            ->join('users', 'homes.id_user', '=', 'users.id')
            ->where('users.id', $user->user_id)
            ->pluck('visiteur.id')
            ->toArray();

        if (!$user) {
            return response()->json(['message' => 'Camera not linked to a user'], 404);
        }

        // ------------- Continue with saving files, calling Python AI, etc. -------------
        if (Storage::disk('public')->exists($cameraFolderPath)) {
            Storage::disk('public')->deleteDirectory($cameraFolderPath);
        }

        $paths = [];
        $fileCounter = 1;

        foreach ($files as $file) {
            $extension = $file->getClientOriginalExtension();
            $filename = $fileCounter . '.' . $extension;
            $path = $file->storeAs($cameraFolderPath, $filename, 'public');
            $paths[] = Storage::path($path); // Full path for Python AI
            $fileCounter++;
        }

        // ------------- Call Python AI and external API as before -------------
        $pythonApiResponse = Http::timeout(120)->post('http://127.0.0.1:5000/identify_secure', [
            'new_images_path' => Storage::disk('public')->path($cameraFolderPath),
            'known_visitors_path' => Storage::disk('public')->path('visitors/' . $user->user_id),
            'allowed_visitor_ids' => $allowedVisitorIds,
        ])->json();

        if (isset($pythonApiResponse['identification']) && $pythonApiResponse['identification'] == "Unknown") {
            // Generate new unknown visitor name
            $lastId = DB::table('visiteur')->max('id') ?? 0;
            $newName = 'unknown#' . ($lastId + 1);

            // Insert new visitor
            $newVisitor = Visiteur::create([
                'nom' => 'Unknown',                    // dummy last name
                'prenom' => 'Visitor',                 // dummy first name
                'num_tel' => '00000000',               // dummy phone
                'email' => 'unknown' . ($lastId + 1) . '@example.com', // dummy email
                'date_visite' => Carbon::now(),        // current timestamp
                'name' => $newName,                    // optional display name
                'id_user' => $user->user_id,
            ]);

            // Get the camera ID
            $cameraId = DB::table('camera')
                ->where('cam_code', $cameraCode)
                ->value('id');

            // Insert into junction table
            DB::table('camera_visiteur')->insert([
                'id_camera' => $cameraId,
                'id_visiteur' => $newVisitor->id,
            ]);

            // Define new storage path: visitors/{user_id}/{new_visiteur_id}/
            $newFolderPath = "visitors/{$user->user_id}/{$newVisitor->id}";

            // Create folder if not exists
            Storage::disk('public')->makeDirectory($newFolderPath);

            // Move all saved images into this new folder
            foreach (Storage::disk('public')->files($cameraFolderPath) as $file) {
                $filename = basename($file);
                Storage::disk('public')->move($file, $newFolderPath . '/' . $filename);
            }

            // Remove old temporary folder
            Storage::disk('public')->deleteDirectory($cameraFolderPath);

            $finalMessage = "New unknown visitor created: {$newName}, id={$newVisitor->id}";
        } else {
            $finalMessage = "Visitor recognized: " . $pythonApiResponse['identification'];
        }

        $externalApiResponse = Http::post('https://b0eb7737e995.ngrok-free.app/receive', [
            'camera_code' => $cameraCode,
            'result' => $pythonApiResponse,
        ])->json();

        return response()->json([
            'message' => count($paths) . ' frames saved and processed',
            'ai_result' => $pythonApiResponse,
            'external_api_result' => $externalApiResponse
        ]);
    }


    // The 'show' method from the previous example still works perfectly
    public function show($camera_code)
    {
        $folderPath = 'visitors/' . $camera_code;
        $files = Storage::disk('public')->files($folderPath);
        $urls = array_map(fn($file) => Storage::url($file), $files);

        // This will sort the URLs naturally (e.g., 1.png, 2.png, ... 10.png)
        natsort($urls);

        return response()->json([
            'camera_code' => $camera_code,
            'photos' => array_values($urls), // Reset array keys for clean JSON
        ]);
    }
    public function get_visiteur($id)
    {
        $user_info = visiteur::select('nom', 'prenom')
            ->where('id', $id)
            ->first();
        return response()->json([
            'name' => $user_info->nom . ' ' . $user_info->prenom
        ]);
    } 
}