<?php

namespace Database\Factories;

use Illuminate\Database\Eloquent\Factories\Factory;

class PaysFactory extends Factory
{
    public function definition(): array
    {
        return [
            'label' => $this->faker->country,
            'continent' => $this->faker->randomElement([
                'Africa',
                'Asia',
                'Europe',
                'North America',
                'South America',
                'Australia',
                'Antarctica'
            ]),

        ];
    }
}
