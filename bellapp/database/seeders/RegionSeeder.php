<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Pays;
use App\Models\Region;

class RegionSeeder extends Seeder
{
    public function run(): void
    {
        Pays::all()->each(function ($pays) {
            Region::factory()->count(2)->create([
                'id_pays' => $pays->id,
            ]);
        });
    }
}
