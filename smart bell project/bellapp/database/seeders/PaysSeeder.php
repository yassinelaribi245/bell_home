<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Pays;

class PaysSeeder extends Seeder
{
    public function run(): void
    {
        Pays::factory()->count(3)->create();
    }
}
