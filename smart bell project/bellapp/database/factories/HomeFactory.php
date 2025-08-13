    <?php

    namespace Database\Factories;

    use Illuminate\Database\Eloquent\Factories\Factory;

    class HomeFactory extends Factory
    {
        public function definition(): array
        {
            return [
                'superficie' => $this->faker->randomFloat(2, 50, 200),
                'longitude' => $this->faker->longitude,
                'latitude' => $this->faker->latitude,
                'num_cam' => $this->faker->numberBetween(1,5),
                'id_user' => null, // We'll assign later
            ];
        }
    }

