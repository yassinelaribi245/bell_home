<?php

use App\Http\Controllers\Api\UserController;
use App\Http\Controllers\Api\villeController;
use App\Http\Controllers\Api\cameraController;
use App\Models\camera;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::middleware('auth.api')->get('/user', function (Request $request) {return $request->user();});
Route::middleware('auth.api')->get('/alluser', [UserController::class, 'index']);
Route::post('/save-fcm-token', [UserController::class, 'save_fcm']);
Route::post('/getUserByCameraCode', [cameraController::class, 'getUserByCameraCode']);
Route::post('/login', [UserController::class, 'login']);
Route::post('/register', [UserController::class, 'register']);
Route::get('/ville', [villeController::class, 'index']);
