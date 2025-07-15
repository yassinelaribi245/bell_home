<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Home;
use App\Models\User;

class HomeSeeder extends Seeder
{
    public function run(): void
    {
        User::all()->each(function($user) {
            Home::factory()->count(2)->create([
                'id_user' => $user->id,
            ]);
        });
    }
}
