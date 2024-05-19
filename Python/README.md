# Python Implementation
This is the implementation of the project in Python. Various libraries such as librosa, keras, tensorflow and numpy have been used in the implementation. A complete list can be found in the `requirement.txt` file.

## Usage
The code has been tested using Python 3.12.3. The following steps have been tested on Linux only:

### 1. Get the testing data
Get the GZTAN dataset from here:<br/>
https://www.kaggle.com/datasets/andradaolteanu/gtzan-dataset-music-genre-classification/data

**Note:** The `jazz.00054.wav` file is corrupted and needs to be downloaded and replaced with the file from here:<br/>
https://www.kaggle.com/datasets/andradaolteanu/gtzan-dataset-music-genre-classification/discussion/158649

### 2. Clone the repository
```bash
git clone https://github.com/thetrashed/music_genre_ai.git
```
Go to the Python directory within the repository.


### 3. Setup the Python Environment
It is recommended to use a virtual environment (e.g. using `virtualenv`):
```bash
virtualenv ./.venv
```
Activate the virtual environment:
```bash
source ./.venv/bin/activate
```
Install the required libraries:
```bash
pip install -r requirements.txt
```

### 4. Train the model / Identify the genre of a new file
For only building the project:
```bash
python train_model.py
```
Once the model has been trained, for the identification of the genre of audio files:
```bash
python new_data_test.py [file(s)]
```
