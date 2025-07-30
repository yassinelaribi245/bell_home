<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class home extends Model
{
    use HasFactory;
    protected $table = 'homes';
    protected $fillable = [
        'superficie',
        'longitude',
        'latitude',
        'num_cam',
        'id_user'
    ];

    public function cameras()
    {
        return $this->hasMany(Camera::class, 'id_home');
    }

    public function users()
    {
        return $this->belongsToMany(User::class, 'user_home', 'id_home', 'id_user');
    }
}
