# Music Genre Identification
This repository contains the code for a music genre identification AI that uses neural networks to identify the genre of a music file. Every aspect of the project has been implemented from scratch, including the reading of the audio files, generation of mel-spectograms, and the neural network as well.

## Usage
The code requires Zig 0.12.0 for compilation. Since it uses `mmap` for mapping files to memory, only Linux is supported by the project. To run the program, the following steps must be carried out.

### 1. Install Zig 0.12.0
https://ziglang.org/download/

### 2. Clone the repository:
```bash
git clone https://github.com/thetrashed/music_genre_ai.git
```

### 3. Build the project
```bash
zig build --release=safe
```

## References
The resources that helped in the creation of the project have been listed [here](RESOURCES.md).
