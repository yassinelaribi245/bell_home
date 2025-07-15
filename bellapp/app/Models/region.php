<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class region extends Model
{
    use HasFactory;
    protected $table = 'region';
    protected $fillable = ['label', 'id_pays'];

    public function country()
    {
        return $this->belongsTo(Pays::class, 'id_pays');
    }

    public function cities()
    {
        return $this->hasMany(ville::class, 'id_region');
    }
}
