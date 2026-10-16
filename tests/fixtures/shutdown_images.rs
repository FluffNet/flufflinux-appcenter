//! Optional loopback-only image server for the shutdown profiling fixture.
//! Complete and cancelled real screenshot workers share this bounded server.
use std::{
    io::{Read, Write},
    net::TcpListener,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread::{self, JoinHandle},
    time::Duration,
};

pub struct Server {
    stopped: Arc<AtomicBool>,
    workers: Vec<JoinHandle<()>>,
}
impl Server {
    pub fn start() -> Self {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        std::env::set_var(
            "APPCENTER_PROFILE_IMAGE_BASE",
            format!("http://{}", listener.local_addr().unwrap()),
        );
        let stopped = Arc::new(AtomicBool::new(false));
        let workers = (0..2).map(|_| {
            let listener = listener.try_clone().unwrap();
            let stopped = stopped.clone();
            thread::spawn(move || {
                while !stopped.load(Ordering::Relaxed) {
                    let Ok((mut socket, _)) = listener.accept() else {
                        thread::sleep(Duration::from_millis(5));
                        continue;
                    };
                    socket.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
                    socket.set_write_timeout(Some(Duration::from_secs(1))).unwrap();
                    let mut request = Vec::new();
                    let mut chunk = [0; 1024];
                    while request.len() < 8192 && !request.windows(4).any(|s| s == b"\r\n\r\n") {
                        match socket.read(&mut chunk) {
                            Ok(0) | Err(_) => break,
                            Ok(n) => request.extend_from_slice(&chunk[..n]),
                        }
                    }
                    if !request.windows(4).any(|s| s == b"\r\n\r\n") { continue; }
                    let body = include_bytes!("shutdown-image.svg");
                    let header = format!("HTTP/1.1 200 OK\r\nContent-Type: image/svg+xml\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len());
                    if socket.write_all(header.as_bytes()).is_err() { continue; }
                    // Leave a real transfer active across navigation/close.
                    if socket.write_all(&body[..body.len()/2]).is_ok() {
                        thread::sleep(Duration::from_millis(150));
                        let _ = socket.write_all(&body[body.len()/2..]);
                    }
                }
            })
        }).collect();
        Self { stopped, workers }
    }
}
impl Drop for Server {
    fn drop(&mut self) {
        self.stopped.store(true, Ordering::Relaxed);
        for worker in self.workers.drain(..) {
            worker.join().unwrap();
        }
    }
}
