<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;

use Illuminate\Database\Eloquent\Model;

class Pays extends Model
{
    use HasFactory;
    protected $table = 'pays';

    protected $fillable = ['label', 'continent'];

    public function regions()
    {
        return $this->hasMany(Region::class, 'id_pays');
    }
}
