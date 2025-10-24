import pandas as pd
import sys
from pathlib import Path

def load_data(file_path):
    """Loads the raw CSV data."""
    print(f"Loading data from {file_path}...")
    try:
        # Use the correct semicolon delimiter
        df = pd.read_csv(file_path, delimiter=';')
        return df
    except FileNotFoundError:
        print(f"Error: Raw data file not found at {file_path}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error loading data: {e}", file=sys.stderr)
        sys.exit(1)

def clean_data(df):
    """
    Cleans the raw retail data based on the following steps:
    1. Renames columns to match the data warehouse model.
    2. Drops rows with missing critical data.
    3. Fills missing categorical data with 'Unknown'.
    4. Converts data types (especially Date and Time).
    5. Finds all "collided" transaction_id's and removes them completely.
    6. Generates 'date_key' (DDMMYYYY), 'time_key' (SSMMHH), and 'month_key' (MMYYYY).
    7. Reorders columns for a clean output file.
    """
    print("Cleaning data...")
    
    # 1. Rename columns
    df.rename(columns={
        'Transaction_ID': 'transaction_id',
        'Total_Purchases': 'quantity',
        'Amount': 'unit_price',
        'Total_Amount': 'line_total_amount',
        'products': 'product_name'
    }, inplace=True)

    # 2. Drop rows with missing critical data
    critical_cols = [
        'transaction_id', 'Customer_ID', 'Date', 'Time', 
        'line_total_amount', 'quantity', 'unit_price'
    ]
    df.dropna(subset=critical_cols, inplace=True)

    # 3. Fill missing categorical data
    categorical_cols = [
        'Income', 'Customer_Segment', 'Feedback', 'Shipping_Method',
        'Payment_Method', 'Order_Status', 'Product_Category',
        'Product_Brand', 'Product_Type'
    ]
    for col in categorical_cols:
        if col in df.columns:
            df[col] = df[col].fillna('Unknown')

    # 4. Convert data types (early, for cleansing step)
    try:
        df['Date_dt'] = pd.to_datetime(df['Date'], format='%m/%d/%Y')
        df['Time_dt'] = pd.to_timedelta(df['Time'].astype(str))
    except Exception as e:
        print(f"Error during Date/Time conversion: {e}. Dropping bad rows.", file=sys.stderr)
        df.dropna(subset=['Date', 'Time'], inplace=True)

        df = df.copy()
        df['Date_dt'] = pd.to_datetime(df['Date'])
        df['Time_dt'] = pd.to_timedelta(df['Time'].astype(str))
    
    df['Customer_ID'] = df['Customer_ID'].astype(int)
    df['transaction_id'] = df['transaction_id'].astype(int)

    # 5. Remove all rows for any collided Transaction_ID
    print(f"Original row count: {len(df)}")
    print("Finding and removing collided transaction_ids...")

    # Flag transactions that have inconsistent customer or date values
    collision_mask = (
        df.groupby('transaction_id')['Customer_ID'].transform('nunique') > 1
    ) | (
        df.groupby('transaction_id')['Date_dt'].transform('nunique') > 1
    )

    n_collided = collision_mask.sum()

    if n_collided:
        print(f"Found {n_collided} collided rows (across {df.loc[collision_mask, 'transaction_id'].nunique()} transaction_ids). Removing them...")
        df = df.loc[~collision_mask].copy() # Keep all rows where collision_mask is False
    else:
        print("No collided transaction_ids found.")

    print(f"New row count after cleansing: {len(df)}")

    # 6. Generate Date and Time keys
    print("Generating date_key (DDMMYYYY), time_key (SSMMHH), and month_key (MMYYYY)...")
    
    df['date_key'] = df['Date_dt'].dt.strftime('%d%m%Y')
    df['month_key'] = df['Date_dt'].dt.strftime('%m%Y')
    
    df['hour_str'] = (df['Time_dt'].dt.components.hours).astype(str).str.zfill(2)
    df['minute_str'] = (df['Time_dt'].dt.components.minutes).astype(str).str.zfill(2)
    df['second_str'] = (df['Time_dt'].dt.components.seconds).astype(str).str.zfill(2)
    
    df['time_key'] = df['second_str'] + df['minute_str'] + df['hour_str']
    
    df.drop(columns=['Date_dt', 'Time_dt', 'hour_str', 'minute_str', 'second_str'], inplace=True)

    # Convert numeric types
    df['quantity'] = df['quantity'].astype('Int64')
    df['Customer_ID'] = df['Customer_ID'].astype('Int64')
    df['transaction_id'] = df['transaction_id'].astype('Int64')
    df['Zipcode'] = df['Zipcode'].fillna(-1).astype(int) # Use -1 for missing zips

    # 7. Select and reorder columns
    final_columns = [
        'transaction_id', 'date_key', 'time_key', 'month_key', 'Customer_ID',
        'quantity', 'unit_price', 'line_total_amount', 'Ratings',
        'product_name', 'Product_Category', 'Product_Brand', 'Product_Type',
        'Payment_Method', 'Shipping_Method', 'Order_Status', 'Feedback',
        'Name', 'Email', 'Phone', 'Address', 'City', 'State', 
        'Zipcode', 'Country', 'Age', 'Gender', 'Income', 'Customer_Segment',
        'Date', 'Time'
    ]
    
    existing_final_columns = [col for col in final_columns if col in df.columns]
    df = df[existing_final_columns]
    
    print(f"Data cleaning finished. Final shape: {df.shape}")
    return df

def save_data(df, output_path):
    """Saves the cleaned DataFrame to a new CSV file."""
    print(f"Saving cleaned data to {output_path}...")
    try:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(output_path, index=False, sep=',')
    except Exception as e:
        print(f"Error saving data: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    input_file = Path("./data/raw/new_retail_data.csv")
    output_file = Path("./data/clean/cleaned_retail_data.csv")
    
    print("--- Starting Data Cleaning ---")
    df = load_data(input_file)
    df_cleaned = clean_data(df)
    save_data(df_cleaned, output_file)
    print("--- Data Cleaning Complete ---")

if __name__ == "__main__":
    main()