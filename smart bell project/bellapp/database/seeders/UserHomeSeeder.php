<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\User;
use App\Models\Home;

class UserHomeSeeder extends Seeder
{
    public function run(): void
    {
        $users = User::all();
        $homes = Home::all();

        foreach ($users as $user) {
            // Attach between 1 and 3 random homes to each user
            $randomHomes = $homes->random(rand(1, 3));
            $user->homes()->attach($randomHomes->pluck('id')->toArray());
        }
    }
}
