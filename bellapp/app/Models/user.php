<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Laravel\Passport\HasApiTokens;

class user extends Authenticatable
{
    use HasApiTokens, HasFactory;
    protected $table = 'users';
    protected $fillable = [
        'nom',
        'prenom',
        'date_naissance',
        'id_ville',
        'code_postal',
        'num_tel',
        'email',
        'fcm',
        'password',
        'role',
        'is_active',
        'is_banned',
        'is_verified',
        'last_login_at',
    ];

    public function city()
    {
        return $this->belongsTo(Pays::class, 'ville_id');
    }

    public function homes()
    {
        return $this->belongsToMany(Home::class, 'user_home', 'id_user', 'id_home');
    }
}
