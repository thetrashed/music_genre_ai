# Music Genre Dectection AI
This repository contains the code for a music genre identification AI that uses neural networks to identify the genre of a music file. The project has been implemented in two languages: Python and Zig. The Python aspect of the project has been implemented by [@mushahidhussian](https://github.com/mushahidhussian).

## Comparison of the Two Implementations
The Zig portion implements everything from the reading of the audio files, to the generation of spectograms, to the neural network without the use of any external libraries. The Python portion on the other hand uses external libraries for all of these tasks (libraries such as numpy, librosa, keras, tensorflow).

Some differences in the implementations other than those mentioned above are as follows:
- The Python implementation uses Mel-cepstral coefficients in the training of the model whereas the Zig implementation simply uses the windowed Fourier transformation.
- The Python implementation of the neural network uses the "relu" and "softmax" activation functions whereas the Zig implementation uses the "relu" and "sigmoid" activation functions.

The Python implementation is much more optimised as compared to the Zig implementation since it uses well-developed libraries such as keras and tensorflow while on the other hand, the Zig implementation implements every aspect from scratch.

## References
The resources that helped in the creation of the project have been listed [here](RESOURCES.md).
