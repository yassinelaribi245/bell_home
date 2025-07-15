<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\User;
use App\Models\Ville;

class UserSeeder extends Seeder
{
    public function run(): void
    {
        $villeIds = Ville::pluck('id')->toArray();

        User::factory()->count(10)->create()->each(function ($user) use ($villeIds) {
            $user->update([
                'id_ville' => $villeIds[array_rand($villeIds)],
            ]);
        });

    }
}
