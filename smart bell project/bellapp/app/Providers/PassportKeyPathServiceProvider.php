<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Laravel\Passport\Passport;

class PassportKeyPathServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        Passport::$keyPath = storage_path();
    }
}
