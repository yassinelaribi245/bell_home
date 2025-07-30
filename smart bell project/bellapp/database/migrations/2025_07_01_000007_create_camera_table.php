<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('camera', function (Blueprint $table) {
            $table->id();
            $table->dateTime("date_creation");
            $table->boolean("is_active");
            $table->boolean("is_recording");
            $table->string("cam_code")->nullable();
            $table->double("longitude");
            $table->double("latitude");
            $table->unsignedBigInteger("id_home");
            $table->timestamps();

            $table->foreign('id_home')->references('id')->on('homes')->onDelete('cascade');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('camera');
    }
};
