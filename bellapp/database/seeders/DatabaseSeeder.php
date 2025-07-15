<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->call([
            PaysSeeder::class,
            RegionSeeder::class,
            VilleSeeder::class,
            UserSeeder::class,
            HomeSeeder::class,
            CameraSeeder::class,
            UserHomeSeeder::class,   // Add this here
        ]);

    }
}
