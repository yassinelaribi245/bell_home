<?php

namespace Database\Factories;

use Illuminate\Database\Eloquent\Factories\Factory;

class VilleFactory extends Factory
{
    public function definition(): array
    {
        return [
            'label' => $this->faker->city,
            'id_region' => null, // Placeholder; will assign later
        ];
    }
}
