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
        Schema::create('camera_visiteur', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('id_visiteur');
            $table->unsignedBigInteger('id_camera');
            $table->timestamps();

            $table->foreign('id_visiteur')->references('id')->on('visiteur')->onDelete('cascade');
            $table->foreign('id_camera')->references('id')->on('camera')->onDelete('cascade');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('camera_visiteur');
    }
};
