<?php
namespace App\Http\Middleware;

use Illuminate\Auth\Middleware\Authenticate as Middleware;

class ApiAuthenticate extends Middleware
{
    protected function redirectTo($request)
    {
        if ($request->expectsJson() || $request->is('api/*')) {
            abort(response()->json(['message' => 'Unauthenticated.'], 401));
        }
        return null;
    }

    protected function authenticate($request, array $guards)
    {
        // Use 'api' guard (Passport) instead of 'sanctum'
        if ($this->auth->guard('api')->check()) {
            $this->auth->shouldUse('api');
            return;
        }
        parent::authenticate($request, $guards);
    }
}
