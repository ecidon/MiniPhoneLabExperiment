from http.server import HTTPServer, BaseHTTPRequestHandler
import cv2
import argparse
import json
from pathlib import Path

def show_full_screen_image(image_path, resolution):
    img = cv2.imread(image_path)
    if img is None:
        return False
    try:
        img = cv2.resize(img, resolution, interpolation=cv2.INTER_CUBIC)
    except:
        return False
    cv2.namedWindow("test", cv2.WND_PROP_FULLSCREEN)
    cv2.setWindowProperty("test", cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN)
    cv2.imshow("test", img)
    cv2.waitKey(1000)
    return True



if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--image-dir', required=True, type=str,
        help='Path to image dir, must be orgenized in folders by labels for example: \"images/backpack/backpack1.jpg\"')
    parser.add_argument('--output-dir', required=True, type=str,
                        help='Path to out dir, must be named as phone')
    parser.add_argument('--resolution', required=True, nargs=2, type=int,
                        help='Screen resolution in the form of: \"--resolution HEIGHT WEIDTH\"')
    parser.add_argument('--ip', required=True, type=str, help='ip to listen on')
    parser.add_argument('--port', required=True, type=int, help='port to listen on')
    args = parser.parse_args()
    
    class RequestHandler(BaseHTTPRequestHandler):
        resolution = tuple(args.resolution)
        image_root = Path(args.image_dir)
        out_root = Path(args.output_dir)

        # To get a list of available files run http command ->
        # GET http://<IP-ADDRESS>:<PORT-NUMBER>/list
        # To have the server present an image on screen run:
        # GET http://<IP-ADDRESS>:<PORT-NUMBER>/<IMAGE_NAME>
        def do_GET(self):
            path = self.path[1:]
            if path == 'list':
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                response = [str(p) for p in self.image_root.rglob('*.jpg')]
                self.wfile.write(json.dumps(response).encode('utf-8'))
                return
            show_full_screen_image(path, self.resolution)
            self.send_response(200)
            self.end_headers()
            return

        # To save an image taken on the phone run http command ->
        # POST http://<IP-ADDRESS>:<PORT-NUMBER>/<IMAGE_NAME> Content-Length: <N> <IMAGE_BYTES>
        # image name should include the label dir for example
        # IMAGE_NAME = backpack/backpack.jpg
        # image will be saved to <args.output_dir>/<IMAGE_NAME>
        def do_POST(self):
            path = self.path[1:]
            out_file = Path(str(self.out_root / path).replace(str(self.image_root),""))
            out_file.parent.mkdir(parents=True, exist_ok=True)
            data_string = self.rfile.read(int(self.headers['Content-Length']))
            self.send_response(200)
            self.end_headers()
            out_file.write_bytes(data_string)

    httpd = HTTPServer((args.ip, args.port), RequestHandler)
    httpd.serve_forever()
    
