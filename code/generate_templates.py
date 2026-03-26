import argparse
import os

REPLAY_DIR = "./code/replay_files"
REPLAY_RANGE = range(1, 241)


def generate_replay_files(libname, cellname):
    os.makedirs(REPLAY_DIR, exist_ok=True)

    for i in REPLAY_RANGE:
        num = f"{i:03d}"
        filepath = os.path.join(REPLAY_DIR, f"replay_{num}.il")

        with open(filepath, "w") as f:
            f.write(f'; replay_{num}.il\n')
            f.write(f'; libname  : {libname}\n')
            if cellname:
                f.write(f'; cellname : {cellname}\n')

        print(f"  created: {filepath}")

    print(f"Done. {len(REPLAY_RANGE)} files generated in {REPLAY_DIR}")


def main():
    parser = argparse.ArgumentParser(description="Generate templates for CAT regression")
    parser.add_argument("--libname", required=True, help="Library name")
    parser.add_argument("--cellname", default=None, help="Cell name (optional)")
    args = parser.parse_args()

    print(f"libname  : {args.libname}")
    if args.cellname:
        print(f"cellname : {args.cellname}")

    generate_replay_files(args.libname, args.cellname)


if __name__ == "__main__":
    main()
