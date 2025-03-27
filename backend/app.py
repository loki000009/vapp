import os
import pickle
import logging
import traceback
import pandas as pd
import numpy as np
from flask import Flask, request, jsonify
from flask_cors import CORS
import xgboost as xgb

# --- App Initialization ---
app = Flask(__name__)
CORS(app, resources={r"/api/*": {"origins": "*"}})  # More flexible CORS configuration

# --- Logging Setup ---
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('app.log', encoding='utf-8')
    ]
)
logger = logging.getLogger(__name__)

# --- Model Loading ---
MODEL_PATH = 'data_type_model.pkl'

def load_model():
    """
    Load the XGBoost model with enhanced error handling and logging.
    
    Returns:
        Loaded model or None if loading fails
    """
    try:
        if not os.path.exists(MODEL_PATH):
            logger.error(f"Model file {MODEL_PATH} does not exist.")
            return None
        
        with open(MODEL_PATH, 'rb') as f:
            model = pickle.load(f)
        
        logger.info(f"XGBoost model loaded successfully from {MODEL_PATH}")
        return model
    
    except (EOFError, pickle.UnpicklingError) as e:
        logger.error(f"Error unpickling model {MODEL_PATH}: {e}")
        logger.error(traceback.format_exc())
    except Exception as e:
        logger.error(f"Unexpected error loading model {MODEL_PATH}: {e}")
        logger.error(traceback.format_exc())
    
    return None

# Global model variable
global_model = load_model()

# Mapping for data types predicted by the model
TYPE_MAP = {0: 'numerical', 1: 'categorical', 2: 'date', 3: 'text'}

def extract_features(df):
    """
    Extracts robust features from a DataFrame for data type prediction.
    
    Args:
        df (pd.DataFrame): Input DataFrame
    
    Returns:
        list: Features for each column
    """
    features = []
    if df.empty:
        return features
    
    for column in df.columns:
        try:
            col_data = df[column].dropna()
            
            if col_data.empty:
                # Default features for empty/all-NA column
                features.append([0.0, 0.0, 0.0, 0.0])
                continue
            
            # Convert to string for consistent processing
            col_data_str = col_data.astype(str)
            
            # Improved feature extraction
            numeric_ratio = col_data_str.str.match(r'^-?\d+(\.\d+)?$').mean()
            date_ratio = col_data_str.str.match(r'\d{2,4}[-/]\d{1,2}[-/]\d{1,2}').mean()
            unique_ratio = col_data.nunique() / len(col_data) if len(col_data) > 0 else 0
            
            # Robust numeric conversion
            numeric_col = pd.to_numeric(col_data, errors='coerce')
            mean_val = numeric_col.mean() if not numeric_col.isna().all() else 0.0
            
            features.append([
                numeric_ratio if pd.notna(numeric_ratio) else 0.0,
                date_ratio if pd.notna(date_ratio) else 0.0,
                unique_ratio if pd.notna(unique_ratio) else 0.0,
                mean_val if pd.notna(mean_val) else 0.0
            ])
        
        except Exception as e:
            logger.warning(f"Error processing column {column}: {e}")
            features.append([0.0, 0.0, 0.0, 0.0])
    
    return features

def suggest_visualizations(df, data_types):
    """
    Suggest visualizations based on predicted data types.
    
    Args:
        df (pd.DataFrame): Input DataFrame
        data_types (list): Predicted data types
    
    Returns:
        dict: Visualization suggestions for each column
    """
    suggestions = {}
    if df.empty:
        return suggestions

    predicted_types_str = [TYPE_MAP.get(t, 'unknown') for t in data_types]
    has_date = 'date' in predicted_types_str
    has_categorical = 'categorical' in predicted_types_str

    for i, dtype_code in enumerate(data_types):
        if i >= len(df.columns):
            break

        col = df.columns[i]
        dtype_str = TYPE_MAP.get(dtype_code, 'unknown')

        if dtype_str == 'numerical':
            if has_date:
                suggestions[col] = ['line']
            elif has_categorical:
                suggestions[col] = ['bar', 'histogram']
            else:
                suggestions[col] = ['histogram']
        elif dtype_str == 'categorical':
            suggestions[col] = ['pie', 'bar']
        elif dtype_str == 'text':
            suggestions[col] = ['word_cloud']

    return suggestions

def analyze_correlations(df, data_types):
    """
    Calculate correlations between numerical columns.
    
    Args:
        df (pd.DataFrame): Input DataFrame
        data_types (list): Predicted data types
    
    Returns:
        dict: Correlation matrix
    """
    try:
        numeric_indices = [i for i, dtype_code in enumerate(data_types) if TYPE_MAP.get(dtype_code) == 'numerical' and i < len(df.columns)]

        if len(numeric_indices) <= 1:
            return {}

        numeric_df = df.iloc[:, numeric_indices].copy()
        for col in numeric_df.columns:
            numeric_df[col] = pd.to_numeric(numeric_df[col], errors='coerce')
        
        numeric_df = numeric_df.dropna(axis=1, how='all')

        if numeric_df.shape[1] <= 1:
            return {}

        correlation_matrix = numeric_df.corr().fillna(0.0)
        return {k: {inner_k: float(inner_v) for inner_k, inner_v in v.items()} 
                for k, v in correlation_matrix.to_dict().items()}
    
    except Exception as e:
        logger.error(f"Error calculating correlations: {e}")
        return {}

def calculate_statistics(df):
    """
    Calculate comprehensive statistics for each column.
    
    Args:
        df (pd.DataFrame): Input DataFrame
    
    Returns:
        dict: Statistics for each column
    """
    stats = {}
    if df.empty:
        return stats

    for column in df.columns:
        col_data = df[column].dropna()
        
        if col_data.empty:
            stats[column] = {'message': 'Column is empty or all NA'}
            continue

        # Attempt numeric conversion
        numeric_col = pd.to_numeric(col_data, errors='coerce')
        
        if not numeric_col.isna().all():
            # Numerical column statistics
            stats[column] = {
                'mean': float(numeric_col.mean()) if pd.notna(numeric_col.mean()) else None,
                'median': float(numeric_col.median()) if pd.notna(numeric_col.median()) else None,
                'std': float(numeric_col.std()) if pd.notna(numeric_col.std()) else None,
                'min': float(numeric_col.min()) if pd.notna(numeric_col.min()) else None,
                'max': float(numeric_col.max()) if pd.notna(numeric_col.max()) else None,
                'type': 'numerical'
            }
        else:
            # Categorical/text column statistics
            value_counts = col_data.value_counts().head(5)
            stats[column] = {
                'unique_values': int(col_data.nunique()),
                'most_common': {str(k): int(v) for k, v in value_counts.items()},
                'type': 'categorical'
            }

    return stats

@app.route('/api/analyze', methods=['POST'])
def analyze_data():
    data = request.json
    if not data:
        return jsonify({'error': 'No data received'}), 400
    """
    Main API endpoint for data analysis.
    Supports complex JSON payload for data analysis.
    """
    # Use the global model 
    current_model = global_model
    
    if current_model is None:
        logger.error("Model is not available. Attempting to reload.")
        current_model = load_model()
        
        if current_model is None:
            return jsonify({
                'error': 'XGBoost model is unavailable. Please train and save a model.',
                'status': 'model_load_failed'
            }), 503

    try:
        # Validate request
        if not request.is_json:
            return jsonify({
                'error': 'Request must be JSON',
                'status': 'invalid_content_type'
            }), 415

        request_data = request.get_json()
        
        # Validate data payload
        if 'data' not in request_data or not isinstance(request_data['data'], list):
            return jsonify({
                'error': 'Invalid data payload. Expected a list of dictionaries.',
                'status': 'invalid_payload'
            }), 400

        # Empty data handling
        list_of_maps = request_data['data']
        if not list_of_maps:
            return jsonify({
                'data_types': {},
                'visualization_suggestions': {},
                'statistics': {},
                'correlations': {}
            }), 200

        # Create DataFrame
        try:
            df = pd.DataFrame(list_of_maps)
            df = df.infer_objects()
        except Exception as df_error:
            logger.error(f"DataFrame creation error: {df_error}")
            return jsonify({
                'error': f'Could not create DataFrame: {str(df_error)}',
                'status': 'dataframe_error'
            }), 400

        # Empty DataFrame handling
        if df.empty:
            return jsonify({
                'data_types': {},
                'visualization_suggestions': {},
                'statistics': {},
                'correlations': {}
            }), 200

        # Feature extraction
        features = extract_features(df)
        if not features:
            return jsonify({
                'error': 'Could not extract features from the data.',
                'status': 'feature_extraction_failed'
            }), 500

        # Predict data types
        try:
            data_types = current_model.predict(features)
        except Exception as predict_error:
            logger.error(f"Prediction error: {predict_error}")
            return jsonify({
                'error': f'Error predicting data types: {str(predict_error)}',
                'status': 'prediction_failed'
            }), 500

        # Prepare response
        data_types_dict = {}
        if len(df.columns) == len(data_types):
            data_types_dict = {df.columns[i]: TYPE_MAP.get(t, 'unknown') for i, t in enumerate(data_types)}
        else:
            min_len = min(len(df.columns), len(data_types))
            data_types_dict = {df.columns[i]: TYPE_MAP.get(data_types[i], 'unknown') for i in range(min_len)}

        response = {
            'data_types': data_types_dict,
            'visualization_suggestions': suggest_visualizations(df, data_types),
            'statistics': calculate_statistics(df),
            'correlations': analyze_correlations(df, data_types)
        }

        return jsonify(response), 200
        

    except Exception as e:
        logger.error(f"Unhandled server error: {e}")
        logger.error(traceback.format_exc())
        return jsonify({
            'error': f'An unexpected server error occurred: {str(e)}',
            'status': 'unexpected_server_error'
        }), 500

        

# Graceful model reloading endpoint
@app.route('/api/reload-model', methods=['POST'])
def reload_model_endpoint():
    """
    Endpoint to manually reload the XGBoost model.
    """
    global global_model
    global_model = load_model()
    
    if global_model is not None:
        return jsonify({
            'message': 'Model reloaded successfully',
            'status': 'success'
        }), 200
    else:
        return jsonify({
            'error': 'Failed to reload model',
            'status': 'model_load_failed'
        }), 500

# --- Main Execution Block ---
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)