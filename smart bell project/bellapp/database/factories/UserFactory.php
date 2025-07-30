<?php

namespace Database\Factories;

use App\Models\Ville;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Facades\Hash;

class UserFactory extends Factory
{
    public function definition(): array
    {
        $plainPassword = 'password123';
        return [
            'nom' => $this->faker->lastName,
            'prenom' => $this->faker->firstName,
            'date_naissance' => $this->faker->date(),
            'id_ville' => function () {return Ville::inRandomOrder()->first()->id;},
            'code_postal' => $this->faker->numberBetween(1000,9999),
            'num_tel' => $this->faker->numerify('#########'),
            'email' => $this->faker->unique()->safeEmail,
            'fcm' => null,
            'password' => Hash::make($plainPassword),
            'role' => 'user',
            'is_active' => true,
            'is_banned' => false,
            'is_verified' => true,
            'last_login_at' => now(),
        ];
    }
}
