#worker_processes 4
timeout 6000
listen 8088
log_dir = "#{ENV['HOME']}"
log_file = File.join log_dir, "lazar.log"
stderr_path log_file
stdout_path log_file
