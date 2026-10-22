"""Capture and process camera feeds with OpenCV.

Usage:
  Python:  python camera/capture.py --source 0
  IP cam:  python camera/capture.py --source "rtsp://user:pass@192.168.1.50:554/stream1"
  Motion:  python camera/capture.py --source 0 --motion --snapshot-dir snapshots
"""

import argparse
import datetime
import os
import cv2


def parse_args():
    parser = argparse.ArgumentParser(description="Capture and process camera feeds")
    parser.add_argument("--source", default=0, help="Camera index (int) or URL (RTSP/USB)")
    parser.add_argument("--resize", type=int, default=640, help="Max frame width after resize")
    parser.add_argument("--fps-output", action="store_true", help="Print processing FPS")
    parser.add_argument("--motion", action="store_true", help="Enable motion detection")
    parser.add_argument("--threshold", type=float, default=5000.0, help="Motion detection threshold")
    parser.add_argument("--snapshot-dir", default="snapshots", help="Dir for motion snapshots")
    parser.add_argument("--show", action="store_true", help="Show live preview window")
    args = parser.parse_args()

    if not isinstance(args.source, int):
        try:
            args.source = int(args.source)
        except ValueError:
            pass

    if args.motion:
        os.makedirs(args.snapshot_dir, exist_ok=True)
    return args


def process(cap, args):
    back_sub = cv2.createBackgroundSubtractorMOG2() if args.motion else None
    cooldown = 0

    while True:
        ok, frame = cap.read()
        if not ok:
            break

        if args.resize > 0:
            h, w = frame.shape[:2]
            if w > args.resize:
                frame = cv2.resize(frame, (args.resize, int(h * args.resize / w)))

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (21, 21), 0)

        if cooldown > 0:
            cooldown -= 1

        if back_sub is not None:
            fg_mask = back_sub.apply(gray)
            _, fg_mask = cv2.threshold(fg_mask, 25, 255, cv2.THRESH_BINARY)
            change = cv2.countNonZero(fg_mask)
            if change > args.threshold:
                print(f"[MOTION] pixels={change}  {datetime.datetime.now().isoformat(timespec='seconds')}")
                if cooldown == 0:
                    path = os.path.join(args.snapshot_dir, datetime.datetime.now().strftime("%Y%m%d_%H%M%S%f") + ".jpg")
                    cv2.imwrite(path, frame)
                    print(f"[SAVED]  {path}")
                    cooldown = 30

        if args.fps_output:
            pass

        if args.show:
            cv2.imshow("capture", frame)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break


def main():
    args = parse_args()
    cap = cv2.VideoCapture(args.source)
    if not cap.isOpened():
        print(f"ERROR: could not open camera source: {args.source}")
        return 1
    try:
        process(cap, args)
    finally:
        cap.release()
        cv2.destroyAllWindows()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())