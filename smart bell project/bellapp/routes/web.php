<?php

use Illuminate\Support\Facades\Route;

Route::get('/storage-app/{path}', function ($path) {
    $file = storage_path('app/public/' . $path); // points to storage/app/public
    if (!file_exists($file)) {
        abort(404);
    }
    return response()->file($file);
})->where('path', '.*');
