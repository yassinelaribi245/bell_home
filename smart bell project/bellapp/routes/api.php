<?php

use App\Http\Controllers\Api\UserController;
use App\Http\Controllers\Api\villeController;
use App\Http\Controllers\Api\cameraController;
use App\Http\Controllers\Api\homeController;
use App\Models\camera;
use App\Models\home;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\VisitorController;

Route::middleware('auth.api')->get('/user', function (Request $request) {return $request->user();});
Route::middleware('auth.api')->get('/alluser', [UserController::class, 'index']);
Route::post('/save-fcm-token', [UserController::class, 'save_fcm']);
Route::post('/delete-fcm-token', [UserController::class, 'delete_fcm']);
Route::post('/getUserByCameraCode', [cameraController::class, 'getUserByCameraCode']);
Route::post('/login', [UserController::class, 'login']);
Route::post('/register', [UserController::class, 'register']);
Route::post('/homes_user', [homeController::class, 'getHomesByEmail']);
Route::post('/cameras_user', [cameraController::class, 'cameras_user']);
Route::post('/login', [UserController::class, 'login']);
Route::get('/ville', [villeController::class, 'index']);
Route::get('/getcameracode', [cameraController::class, 'getCameraCode']);
// NEW: Camera status update routes for Node.js server
Route::post('/update-camera-status', [cameraController::class, 'updateCameraStatus']);
Route::post('/camera-connected', [cameraController::class, 'cameraConnected']);
Route::post('/camera-disconnected', [cameraController::class, 'cameraDisconnected']);
Route::post('/camera-status-update', [cameraController::class, 'cameraStatusUpdate']);
Route::post('/addhome', [homeController::class, 'store']);
Route::post('/addcamera', [cameraController::class, 'store']);
Route::delete('/deletecamera/{cameraId}', [cameraController::class, 'destroy']);
Route::get('/homecameras/{homeId}', [homeController::class, 'getCamerasByHomeId']);
Route::delete('/deletehome/{homeId}', [homeController::class, 'destroy']);
Route::get('/userinfo/{email}', [userController::class, 'get_user']);
Route::post('/upload-frames', [VisitorController::class, 'store']);
Route::get('/getNameVisiteur/{id}', [VisitorController::class, 'get_visiteur']);