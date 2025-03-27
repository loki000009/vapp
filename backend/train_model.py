import os
import pickle
import logging
import traceback
import pandas as pd
import numpy as np
import xgboost as xgb # Or from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, accuracy_score
from sklearn.preprocessing import LabelEncoder # To handle potential non-numeric labels if needed

# --- Configuration ---
# !!! MUST SET THIS to the directory containing your sample CSV/Excel files !!!
SAMPLE_DATA_DIR = 'datasets/'

# --- Logging Setup ---
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('train_model.log', encoding='utf-8') # Log training process
    ]
)
logger = logging.getLogger(__name__)

# --- Feature Extraction Function (Copied from app.py for consistency) ---
def extract_features(df):
    """
    Extracts robust features from a DataFrame for data type prediction.
    (Ensure this is identical to the one used in app.py)
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
            date_ratio = col_data_str.str.match(r'\d{2,4}[-/]\d{1,2}[-/]\d{1,2}').mean() # Basic date check
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
            logger.warning(f"Error processing column {column} during feature extraction: {e}")
            features.append([0.0, 0.0, 0.0, 0.0]) # Default features on error
    
    return features

# --- Data Loading and Labeling ---
logger.info("Starting data loading and feature extraction...")

# Mapping: IMPORTANT - Must match the one in app.py
LABEL_MAP = {'numerical': 0, 'categorical': 1, 'date': 2, 'text': 3}
INVERSE_TYPE_MAP = {v: k for k, v in LABEL_MAP.items()}

X_features = [] # To store feature vectors for each column
y_labels = [] # To store the TRUE label (0, 1, 2, or 3) for each column

if not os.path.isdir(SAMPLE_DATA_DIR):
     logger.error(f"Training data directory not found: {SAMPLE_DATA_DIR}")
     exit(1)

processed_files_count = 0
processed_columns_count = 0

for filename in os.listdir(SAMPLE_DATA_DIR):
    filepath = os.path.join(SAMPLE_DATA_DIR, filename)
    df_sample = None
    
    try:
        logger.info(f"Processing file: {filename}")
        if filename.lower().endswith('.csv'):
            # Try different encodings if needed
            try:
                df_sample = pd.read_csv(filepath, low_memory=False)
            except UnicodeDecodeError:
                logger.warning(f"UTF-8 decoding failed for {filename}, trying latin1.")
                df_sample = pd.read_csv(filepath, low_memory=False, encoding='latin1')
        elif filename.lower().endswith(('.xlsx', '.xls')):
            df_sample = pd.read_excel(filepath, sheet_name=None) # Read all sheets
            if isinstance(df_sample, dict): # If multiple sheets, combine or process first one
                 if not df_sample:
                     logger.warning(f"Excel file {filename} has no sheets.")
                     continue
                 df_sample = df_sample[list(df_sample.keys())[0]] # Process only the first sheet
        else:
            logger.debug(f"Skipping non-CSV/Excel file: {filename}")
            continue # Skip other files

        if df_sample is None or df_sample.empty:
            logger.warning(f"Skipping empty or unreadable file/sheet: {filename}")
            continue

        processed_files_count += 1

        # --- !!! CRITICAL: Adapt Labeling Logic Here !!! ---
        # This section determines the TRUE label for each column.
        # The example below uses simple heuristics based on column names and dtypes.
        # YOU MUST MODIFY THIS TO BE ACCURATE FOR YOUR SAMPLE DATA.
        # Consider manual mapping, more complex rules, or pre-labeled data if possible.
        for col_name in df_sample.columns:
            true_label = None
            col_dtype_kind = df_sample[col_name].dtype.kind

            # Heuristic 1: Column Name Check (Adapt keywords)
            col_name_lower = str(col_name).lower()
            if 'date' in col_name_lower or 'time' in col_name_lower or '_dt' in col_name_lower:
                true_label = LABEL_MAP['date']
            elif 'id' in col_name_lower or 'code' in col_name_lower or 'identifier' in col_name_lower:
                true_label = LABEL_MAP['categorical'] # Often IDs are treated as categorical
            elif 'name' in col_name_lower or 'desc' in col_name_lower or 'text' in col_name_lower or 'comment' in col_name_lower:
                 true_label = LABEL_MAP['text']
            elif 'category' in col_name_lower or 'type' in col_name_lower or 'status' in col_name_lower:
                 true_label = LABEL_MAP['categorical']

            # Heuristic 2: Initial Pandas dtype Check (if no name match)
            if true_label is None:
                if col_dtype_kind in ['i', 'f', 'u']: # Integer, Float, Unsigned Integer
                    # Could add checks here: if unique ratio is very high, maybe it's an ID (categorical)?
                     if df_sample[col_name].nunique() / len(df_sample[col_name].dropna()) > 0.95 and len(df_sample[col_name].dropna()) > 10:
                         true_label = LABEL_MAP['categorical'] # High uniqueness suggests ID
                     else:
                         true_label = LABEL_MAP['numerical']
                elif col_dtype_kind == 'O': # Object type - could be categorical or text
                     # Guess based on uniqueness - low uniqueness -> categorical, high -> text?
                     # This is a common but potentially inaccurate heuristic.
                     if df_sample[col_name].nunique() / len(df_sample[col_name].dropna()) < 0.5: # Arbitrary threshold
                          true_label = LABEL_MAP['categorical']
                     else:
                          true_label = LABEL_MAP['text']
                elif col_dtype_kind in ['M', 'm']: # Datetime types
                     true_label = LABEL_MAP['date']
                else:
                     logger.warning(f"Could not determine label for column '{col_name}' (dtype kind: {col_dtype_kind}) in {filename}. Defaulting to 'text'.")
                     true_label = LABEL_MAP['text'] # Default fallback

            # --- End of Labeling Logic ---

            # Extract features for this column
            col_df = df_sample[[col_name]]
            features = extract_features(col_df)
            if features:
                X_features.append(features[0]) # Get the feature list
                y_labels.append(true_label)
                processed_columns_count += 1
            else:
                 logger.warning(f"Could not extract features for column '{col_name}' in file {filename}")

    except Exception as e:
        logger.error(f"Error processing file {filepath}: {e}", exc_info=True)

logger.info(f"Finished processing {processed_files_count} files.")
logger.info(f"Generated {len(X_features)} feature sets for {processed_columns_count} columns.")

if not X_features or not y_labels or len(X_features) != len(y_labels):
    logger.error("Feature extraction or labeling failed. Not enough data to train. Exiting.")
    exit(1)

# --- Model Training & Evaluation ---
logger.info("Splitting data into training and testing sets...")
try:
    # Stratify ensures class distribution is similar in train/test sets, important for imbalanced data
    X_train, X_test, y_train, y_test = train_test_split(
        X_features, y_labels, test_size=0.25, random_state=42, stratify=y_labels
    )
    logger.info(f"Training set size: {len(X_train)}, Test set size: {len(X_test)}")
except ValueError as split_error:
     logger.error(f"Could not split data, likely too few samples per class: {split_error}. Try getting more diverse data. Exiting.")
     exit(1)


logger.info("Training XGBoost model...")
# You can add hyperparameters here if needed, e.g., max_depth, learning_rate
model = xgb.XGBClassifier(
    objective='multi:softmax',
    num_class=len(LABEL_MAP), # Number of classes based on your map
    eval_metric='mlogloss',
    use_label_encoder=False, # Recommended for newer XGBoost versions
    random_state=42
)

try:
    model.fit(np.array(X_train), np.array(y_train)) # Models expect NumPy arrays
    logger.info("Model training completed.")
except Exception as train_error:
    logger.error(f"Error during model training: {train_error}", exc_info=True)
    exit(1)

# --- Evaluation ---
logger.info("Evaluating model performance on the test set...")
try:
    y_pred = model.predict(np.array(X_test))

    accuracy = accuracy_score(y_test, y_pred)
    report = classification_report(
        y_test,
        y_pred,
        labels=list(LABEL_MAP.values()), # Ensure correct label order
        target_names=list(LABEL_MAP.keys()), # Use names from map
        zero_division=0 # Handle cases where a class might not be in y_test/y_pred
    )

    logger.info(f"\nModel Accuracy on Test Set: {accuracy:.4f}\n")
    logger.info("Classification Report:\n" + report)

except Exception as eval_error:
    logger.error(f"Error during model evaluation: {eval_error}", exc_info=True)
    # Continue to saving even if evaluation fails? Or exit? Decide based on requirements.
    accuracy = 0 # Set accuracy low if evaluation failed

# --- Model Saving ---
# Define a minimum acceptable accuracy threshold
ACCURACY_THRESHOLD = 0.75 # Adjust as needed

if accuracy >= ACCURACY_THRESHOLD:
    logger.info(f"Accuracy ({accuracy:.4f}) meets threshold ({ACCURACY_THRESHOLD}). Saving model...")
    try:
        with open('data_type_model.pkl', 'wb') as f:
            pickle.dump(model, f)
        logger.info("Trained XGBoost model saved successfully to data_type_model.pkl")
    except Exception as save_error:
        logger.error(f"Error saving model: {save_error}", exc_info=True)
else:
    logger.warning(f"Model accuracy ({accuracy:.4f}) is below threshold ({ACCURACY_THRESHOLD}). Model not saved.")
    logger.warning("Consider improving features, getting more/better labeled data, or tuning hyperparameters.")