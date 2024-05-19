import librosa
import librosa.feature

import numpy as np

import keras.models as models
from keras.models import Sequential
from keras.layers import Dense, Activation
from keras.utils import to_categorical

import sys


def extract_features_song(f):
    y, _ = librosa.load(f)

    # get Mel-frequency cepstral coefficients
    mfcc = librosa.feature.mfcc(y=y)
    # normalise values between -1, 1
    mfcc /= np.amax(np.absolute(mfcc))

    return np.ndarray.flatten(mfcc)[:25000]


model = models.load_model("model.keras", compile=True)

files = sys.argv[1:]

all_labels = [
    "blues",
    "classical",
    "country",
    "disco",
    "hiphop",
    "jazz",
    "metal",
    "pop",
    "reggae",
    "rock",
]

# Loop over all files in the arguments passed via the cli
for file in files:
    try:
        test_music = np.stack([extract_features_song(file)])

        predictions = model.predict(test_music).flatten()
        print(f"\n{file}:")
        for label, prediction in zip(all_labels, predictions):
            print(f"{label}: {prediction:.2f}")
    except:
        print(f"Error in analysing {file}")
