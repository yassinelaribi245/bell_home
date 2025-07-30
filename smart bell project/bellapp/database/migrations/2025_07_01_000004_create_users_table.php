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
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            $table->string('nom') ;
            $table->string('prenom');
            $table->date('date_naissance');
            $table->unsignedBigInteger('id_ville');
            $table->Integer('code_postal');
            $table->Integer('num_tel');
            $table->string("email");
            $table->string("fcm")->nullable();
            $table->string("password");
            $table->string('role');
            $table->boolean('is_active');
            $table->boolean('is_banned');
            $table->boolean('is_verified');
            $table->dateTime('last_login_at');
            $table->timestamps();

            $table->foreign('id_ville')->references('id')->on('ville');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('user');
    }
};
