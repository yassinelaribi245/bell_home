<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Camera;
use App\Models\Home;

class CameraSeeder extends Seeder
{
    public function run(): void
    {
        Home::all()->each(function($home) {
            Camera::factory()->count(3)->create([
                'id_home' => $home->id,
            ]);
        });
    }
}
