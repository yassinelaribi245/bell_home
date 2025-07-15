<?php

namespace Database\Factories;

use Illuminate\Database\Eloquent\Factories\Factory;

class RegionFactory extends Factory
{
    public function definition(): array
    {
        return [
            'label' => $this->faker->state,
            'id_pays' => null, // Placeholder; will assign later
        ];
    }
}
