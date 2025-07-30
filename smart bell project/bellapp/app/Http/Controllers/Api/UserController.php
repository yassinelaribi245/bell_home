<?php

namespace App\Http\Controllers\Api;
use App\Models\user;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class UserController extends Controller
{
    /**
     * Display a listing of the resource.
     */
    public function register(Request $request)
    {
        // Validate input
        $validated = $request->validate([
            'nom' => 'required|string|max:255',
            'prenom' => 'required|string|max:255',
            'date_naissance' => 'required|date',
            'id_ville' => 'required|integer',
            'code_postal' => 'required|integer',
            'num_tel' => 'required|integer',
            'email' => 'required|email|unique:users,email',
            'password' => 'required|string|min:6',
        ]);

        // Create user
        $user = User::create([
            'nom' => $validated['nom'],
            'prenom' => $validated['prenom'],
            'date_naissance' => $validated['date_naissance'],
            'id_ville' => $validated['id_ville'],
            'code_postal' => $validated['code_postal'],
            'num_tel' => $validated['num_tel'],
            'email' => $validated['email'],
            'password' => \Illuminate\Support\Facades\Hash::make($validated['password']),
            'role' => "user",
            'is_active' => 1,
            'is_banned' => 0,
            'is_verified' => 1,
            'last_login_at' => now(),
        ]);

        // Generate token
        $tokenResult = $user->createToken('api_token');
        $token = $tokenResult->accessToken;


        return response()->json([
            'token' => $token,
            'user' => $user,
        ]);
    }




    public function login(Request $request)
    {
        // Validate input
        $request->validate([
            'email' => 'required|email',
            'password' => 'required',
        ]);

        // Find user by email
        $user = User::where('email', $request->email)->first();

        // Verify hashed password
        if (!$user || !Hash::check($request->password, $user->password)) {
            return response()->json([
                'message' => 'Invalid credentials',
            ], 401);
        }

        // Create token
        $tokenResult = $user->createToken('api_token');
        $token = $tokenResult->accessToken;


        // Return token and user info
        return response()->json([
            'token' => $token,
            'user' => $user,
        ]);
    }
    public function save_fcm(Request $request)
{
    // Validate input
    $validated = $request->validate([
        'fcm_token' => 'required|string',
        'email' => 'required|email',
    ]);

    // Update the user's FCM token
    $updated = User::where('email', "=",$validated['email'])
        ->update(['fcm' => $validated['fcm_token']]);

    if ($updated) {
        return response()->json(['message' => 'FCM token saved successfully.'], 200);
    } else {
        return response()->json(['message' => 'User not found.'], 404);
    }
}
public function delete_fcm(Request $request)
{
    // Validate input
    $validated = $request->validate([
        'email' => 'required|email',
    ]);

    // Update the user's FCM token
    $updated = User::where('email', "=",$validated['email'])
        ->update(['fcm' => null]);

    if ($updated) {
        return response()->json(['message' => 'FCM token deleted successfully.'], 200);
    } else {
        return response()->json(['message' => 'User not found.'], 404);
    }
}


    public function index()
    {
        return user::all();
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
