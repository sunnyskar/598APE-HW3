#!/bin/bash

# Configuration
BRANCHES=("original" "opt1" "main")

# Test cases in specific order: (case_name, bodies, timesteps)
TEST_CASES=(
    "case1 1000 5000"
    "case2 5 1000000000"
    "case3 1000 500000"
)

RUNS=3

# Calculate total number of runs for progress bar
TOTAL_RUNS=$((${#BRANCHES[@]} * ${#TEST_CASES[@]} * RUNS))
CURRENT_RUN=0

# Progress bar function
progress_bar() {
    local progress=$1
    local total=$2
    local width=50
    local percentage=$((progress * 100 / total))
    local completed=$((width * progress / total))
    local remaining=$((width - completed))
    
    printf "\rProgress: ["
    printf "%${completed}s" | tr ' ' '#'
    printf "%${remaining}s" | tr ' ' '-'
    printf "] %d%%" $percentage
}

# Create results directory
mkdir -p benchmark_results

# Function to run benchmark for a specific configuration
run_benchmark() {
    local branch=$1
    local planets=$2
    local timesteps=$3
    local case_name=$4
    local run=$5
    
    echo -e "\n\nRunning benchmark: branch=$branch, case=$case_name (planets=$planets, timesteps=$timesteps), run=$run"
    
    # Checkout the branch
    git checkout $branch
    
    # Compile
    make clean
    make
    
    # Run and capture time
    echo "Running program with: ./main.exe $planets $timesteps"
    output=$(./main.exe $planets $timesteps)
    echo "Raw program output:"
    echo "$output"
    time=$(echo "$output" | grep "Total time to run simulation" | awk '{print $6}')
    echo "Captured time: $time"
    
    # Save result
    echo "$branch,$case_name,$planets,$timesteps,$run,$time" >> benchmark_results/results.csv
    
    # Update progress
    CURRENT_RUN=$((CURRENT_RUN + 1))
    progress_bar $CURRENT_RUN $TOTAL_RUNS
}

# Print benchmark configuration
echo "Benchmark Configuration:"
echo "======================="
echo "Branches: ${BRANCHES[*]}"
echo "Test Cases:"
for test_case in "${TEST_CASES[@]}"; do
    read case_name planets timesteps <<< "$test_case"
    echo "  $case_name: $planets bodies, $timesteps timesteps"
done
echo "Runs per configuration: $RUNS"
echo "Total runs: $TOTAL_RUNS"
echo -e "\nStarting benchmark...\n"

# Create CSV header
echo "branch,case,planets,timesteps,run,time" > benchmark_results/results.csv

# Run benchmarks for each case sequentially
for test_case in "${TEST_CASES[@]}"; do
    read case_name planets timesteps <<< "$test_case"
    echo -e "\n\n=== Running Case $case_name ==="
    
    for branch in "${BRANCHES[@]}"; do
        echo -e "\nRunning on branch: $branch"
        for ((run=1; run<=RUNS; run++)); do
            run_benchmark $branch $planets $timesteps $case_name $run
        done
    done
done

echo -e "\n\nGenerating plots..."

# Generate graphs using Python
cat > benchmark_results/generate_graphs.py << 'EOF'
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Read data
df = pd.read_csv('results.csv')

# Set style
sns.set_style("whitegrid")
plt.rcParams.update({'font.size': 12})

# Create directory for plots
import os
os.makedirs('plots', exist_ok=True)

# Calculate average times
df_avg = df.groupby(['branch', 'case', 'planets', 'timesteps'])['time'].agg(['mean', 'std']).reset_index()

# Plot: Runtime comparison for each case
plt.figure(figsize=(12, 6))
bar_width = 0.25  # Adjusted for 3 branches
cases = df_avg['case'].unique()
x = range(len(cases))

for i, branch in enumerate(df_avg['branch'].unique()):
    branch_data = df_avg[df_avg['branch'] == branch]
    plt.bar([xi + i*bar_width for xi in x], 
            branch_data['mean'], 
            bar_width,
            label=branch,
            yerr=branch_data['std'],
            capsize=5)

plt.xlabel('Test Cases')
plt.ylabel('Runtime (seconds)')
plt.title('Runtime Comparison Across Test Cases')
plt.xticks([xi + bar_width for xi in x], 
           [f"{row['case']}\n({row['planets']} bodies,\n{row['timesteps']} steps)" 
            for _, row in df_avg[df_avg['branch'] == df_avg['branch'].unique()[0]].iterrows()])
plt.legend()
plt.tight_layout()
plt.savefig('plots/runtime_comparison.png')
plt.close()

# Plot: Runtime distribution
plt.figure(figsize=(12, 6))
sns.boxplot(data=df, x='case', y='time', hue='branch')
plt.xticks(range(len(cases)), 
          [f"{row['case']}\n({row['planets']} bodies,\n{row['timesteps']} steps)" 
           for _, row in df_avg[df_avg['branch'] == df_avg['branch'].unique()[0]].iterrows()],
          rotation=45)
plt.title('Runtime Distribution by Test Case')
plt.tight_layout()
plt.savefig('plots/runtime_distribution.png')
plt.close()

# Calculate speedup relative to original
print("\nSpeedup Analysis:")
print("================")
for case in cases:
    print(f"\nCase: {case}")
    case_data = df[df['case'] == case]
    original_time = case_data[case_data['branch'] == 'original']['time'].mean()
    for branch in df_avg['branch'].unique():
        if branch != 'original':
            opt_time = case_data[case_data['branch'] == branch]['time'].mean()
            speedup = original_time / opt_time
            print(f"{branch} speedup: {speedup:.2f}x")

# Print summary statistics
print("\nSummary Statistics:")
print("==================")
for case in cases:
    print(f"\nCase: {case}")
    case_data = df[df['case'] == case]
    summary = case_data.groupby('branch')['time'].agg(['mean', 'std', 'min', 'max'])
    print(summary)
EOF

# Run Python script to generate graphs
cd benchmark_results
python3 generate_graphs.py
cd ..

echo -e "\nBenchmark complete! Results saved in benchmark_results/"
echo "Plots saved as:"
echo "  - benchmark_results/plots/runtime_comparison.png"
echo "  - benchmark_results/plots/runtime_distribution.png" 