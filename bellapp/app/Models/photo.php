<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class photo extends Model
{
    protected $table = 'photos';
    protected $fillable = ['id_visiteur', 'url'];

    public function visiteur()
    {
        return $this->belongsTo(Visiteur::class, 'id_visiteur');
    }
}
