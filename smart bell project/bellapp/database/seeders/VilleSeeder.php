<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Region;
use App\Models\Ville;

class VilleSeeder extends Seeder
{
    public function run(): void
    {
        Region::all()->each(function ($region) {
            Ville::factory()->count(3)->create([
                'id_region' => $region->id,
            ]);
        });
    }
}
