<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class visiteur extends Model
{
    protected $table = 'visiteur';
    protected $fillable = ['date_visite', 'nom', 'prenom', 'num_tel', 'email'];

    public function cameras()
    {
        return $this->belongsToMany(Camera::class, 'camera_visiteur', 'id_visiteur', 'id_camera')->withTimestamps();
    }

    public function photos()
    {
        return $this->hasMany(Photo::class, 'id_visiteur');
    }
}
