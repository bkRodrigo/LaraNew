<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;

class DevDumpServerCommand extends Command
{
    protected $signature = 'dev:dump-server';

    protected $description = 'Start the local Symfony VarDumper server for dump() output.';

    public function handle(): int
    {
        if (! app()->environment('local')) {
            $this->error('dev:dump-server is intended for local development only.');
            return self::FAILURE;
        }

        $binary = base_path('vendor/bin/var-dump-server');

        if (! file_exists($binary)) {
            $this->error('Could not find vendor/bin/var-dump-server.');
            $this->line('Run composer install (or composer require --dev symfony/var-dumper).');
            return self::FAILURE;
        }

        $this->info('Starting Symfony VarDumper server...');
        $this->line("Binary: {$binary}");
        $this->line('Press Ctrl+C to stop.' . PHP_EOL);

        $command = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($binary);
        passthru($command, $exitCode);

        return $exitCode === 0 ? self::SUCCESS : self::FAILURE;
    }
}
