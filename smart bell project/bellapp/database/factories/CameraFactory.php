<?php

namespace Database\Factories;

use Illuminate\Database\Eloquent\Factories\Factory;

class CameraFactory extends Factory
{
    public function definition(): array
    {
        return [
            'date_creation' => $this->faker->dateTime(),
            'is_active' => $this->faker->boolean,
            'is_recording' => $this->faker->boolean,
            'longitude' => $this->faker->longitude,
            'cam_code' => null,
            'latitude' => $this->faker->latitude,
            'id_home' => null, // Important: don't hardcode 1
        ];
    }
}
