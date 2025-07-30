<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class camera extends Model
{
    use HasFactory;
    protected $table = 'camera';
    protected $fillable = ['date_creation', 'is_active', 'cam_code', 'is_recording', 'longitude', 'latitude', 'id_home'];

    public function home()
    {
        return $this->belongsTo(Home::class, 'id_home');
    }

    public function visiteurs()
    {
        return $this->belongsToMany(Visiteur::class, 'camera_visiteur', 'id_camera', 'id_visiteur')->withTimestamps();
    }
}
