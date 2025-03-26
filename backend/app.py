from flask import Flask, request, jsonify
from flask_cors import CORS
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
import pickle
import os
from werkzeug.utils import secure_filename

app = Flask(__name__)
CORS(app)

UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'csv', 'xlsx', 'xls'}

if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

# Load or train the Random Forest model
model_path = 'data_type_model.pkl'
if os.path.exists(model_path):
    model = pickle.load(open(model_path, 'rb'))
else:
    # Placeholder: Train a simple model (replace with real data)
    from sklearn.datasets import make_classification
    X, y = make_classification(n_samples=100, n_features=4, random_state=42)
    model = RandomForestClassifier(random_state=42)
    model.fit(X, y)
    pickle.dump(model, open(model_path, 'wb'))

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def extract_features(df):
    features = []
    for column in df.columns:
        col_data = df[column].dropna().astype(str)
        feat = [
            col_data.str.match(r'^-?\d*\.?\d+$').mean(),  # Numeric ratio
            col_data.str.match(r'\d{2,4}[-/]\d{2}[-/]\d{2,4}').mean(),  # Date ratio
            col_data.nunique() / len(col_data),  # Unique ratio
            pd.to_numeric(col_data, errors='coerce').mean() or 0  # Mean
        ]
        features.append(feat)
    return features

def suggest_visualizations(data_types):
    type_map = {0: 'numerical', 1: 'categorical', 2: 'date', 3: 'text'}
    suggestions = {}
    for i, dtype in enumerate(data_types):
        col = df.columns[i]
        dtype_str = type_map[dtype]
        if dtype_str == 'numerical':
            if 'date' in [type_map[t] for t in data_types]:
                suggestions[col] = ['line']
            elif 'categorical' in [type_map[t] for t in data_types]:
                suggestions[col] = ['bar']
        elif dtype_str == 'categorical':
            suggestions[col] = ['pie']
        elif dtype_str == 'text':
            suggestions[col] = ['word_cloud']
    return suggestions

def analyze_correlations(df, data_types):
    numeric_columns = [col for col, dtype in enumerate(data_types) if dtype == 0]
    if len(numeric_columns) > 1:
        correlation_matrix = df.iloc[:, numeric_columns].corr()
        return correlation_matrix.to_dict()
    return {}

@app.route('/api/analyze', methods=['POST'])
def analyze_data():
    global df  # For use in suggest_visualizations
    try:
        # Check if JSON data is sent (parsed by Flutter)
        if request.is_json:
            data = request.json['data']
            df = pd.DataFrame(data[1:], columns=data[0])
        else:
            if 'file' not in request.files:
                return jsonify({'error': 'No file part'}), 400
            file = request.files['file']
            if file.filename == '':
                return jsonify({'error': 'No selected file'}), 400
            if not allowed_file(file.filename):
                return jsonify({'error': 'File type not allowed'}), 400
            filename = secure_filename(file.filename)
            filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            file.save(filepath)
            if filename.endswith('.csv'):
                df = pd.read_csv(filepath)
            else:
                df = pd.read_excel(filepath)
            os.remove(filepath)

        # Extract features and predict data types
        features = extract_features(df)
        data_types = model.predict(features)

        # Suggest visualizations
        viz_suggestions = suggest_visualizations(data_types)

        # Basic statistics
        stats = {}
        for column in df.columns:
            if pd.api.types.is_numeric_dtype(df[column]):
                stats[column] = {
                    'mean': float(df[column].mean()) if not pd.isna(df[column].mean()) else 0,
                    'median': float(df[column].median()) if not pd.isna(df[column].median()) else 0,
                    'std': float(df[column].std()) if not pd.isna(df[column].std()) else 0,
                    'min': float(df[column].min()) if not pd.isna(df[column].min()) else 0,
                    'max': float(df[column].max()) if not pd.isna(df[column].max()) else 0
                }
            else:
                stats[column] = {
                    'unique_values': int(df[column].nunique()),
                    'most_common': df[column].value_counts().head(5).to_dict()
                }

        # Correlations
        correlations = analyze_correlations(df, data_types)

        return jsonify({
            'data_types': {df.columns[i]: type_map[t] for i, t in enumerate(data_types)},
            'visualization_suggestions': viz_suggestions,
            'statistics': stats,
            'correlations': correlations
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)