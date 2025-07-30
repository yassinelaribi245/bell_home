<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class ville extends Model
{
    use HasFactory;
    protected $table = 'ville';
    protected $fillable = ['label', 'id_region'];

    public function region()
    {
        return $this->belongsTo(Region::class, 'id_region');
    }

    public function users()
    {
        return $this->hasMany(user::class, 'ville_id');
    }
}
