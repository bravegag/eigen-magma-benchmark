//============================================================================
// Name        : benchmark_main.cc
// Author      : Giovanni Azua (bravegag@hotmail.com)
// Since       : 25.07.2013
// Description : Main application for benchmarking Eigen with MAGMA and MKL
//============================================================================

#include <assert.h>
#include <iostream>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string>
#include <vector>

#include <boost/accumulators/accumulators.hpp>
#include <boost/accumulators/statistics/stats.hpp>
#include <boost/accumulators/statistics/mean.hpp>
#include <boost/accumulators/statistics/variance.hpp>

#include <boost/program_options/cmdline.hpp>
#include <boost/program_options/config.hpp>
#include <boost/program_options/environment_iterator.hpp>
#include <boost/program_options/eof_iterator.hpp>
#include <boost/program_options/errors.hpp>
#include <boost/program_options/option.hpp>
#include <boost/program_options/options_description.hpp>
#include <boost/program_options/parsers.hpp>
#include <boost/program_options/positional_options.hpp>
#include <boost/program_options/value_semantic.hpp>
#include <boost/program_options/variables_map.hpp>
#include <boost/program_options/version.hpp>

#include <boost/chrono.hpp>

#include <boost/tokenizer.hpp>

#include <Eigen/Dense>

/**
 * Define reusable Eigen vector and matrix types.
 */
template<typename T>
struct BenchType {
	typedef Eigen::Matrix<T, Eigen::Dynamic, Eigen::Dynamic, Eigen::ColMajor> MatrixX;
	typedef Eigen::Matrix<T, Eigen::Dynamic, 1, Eigen::ColMajor> VectorX;
};

typedef BenchType<double>::MatrixX MatrixXd;
typedef BenchType<double>::VectorX VectorXd;

using namespace std;
using namespace boost::accumulators;
using namespace boost::chrono;
namespace po = boost::program_options;

typedef double (*workload_type)(long);

typedef accumulator_set<double, stats<tag::mean, tag::variance> > bench_accumulator;
static bench_accumulator real_time_acc, gflops_acc;

// reusable vector and matrices
MatrixXd A, B, C, L;
VectorXd a, b, c;
Eigen::ColPivHouseholderQR<MatrixXd> Aqr;

/// Generic benchmarking
/**
 * Generic benchmarking, implement the different workload types according to the expected signature.
 */
static void run_benchmark(long N, int warm_ups, int num_runs, workload_type workload) {
	// warm up runs
	for (int i = 0; i < warm_ups; ++i) {
		// invoke workload
		(*workload)(N);

		fprintf(stderr, ".");
		fflush (stderr);
	}

	// actual measurements
	for (int i = 0; i < num_runs; ++i) {
		double real_time, cpu_time, gflops;
		double flop_count;
		system_clock::time_point start;

		// benchmark using high-resolution timer
		start = system_clock::now();

		// invoke workload
		flop_count = (*workload)(N);

		// use high-resolution timer
		duration<double> sec = system_clock::now() - start;
		real_time = sec.count();
		gflops = flop_count / (1e9 * real_time);

		// feed the accumulators
		real_time_acc(real_time);
		gflops_acc(gflops);

		fprintf(stderr, ".");
		fflush (stderr);
	}
}

EIGEN_DONT_INLINE
static double dgemm(long N) {
	C = A * B;
	// flops see http://www.netlib.org/lapack/lawnspdf/lawn41.pdf page 120
	return 2 * N * N * N;
}

EIGEN_DONT_INLINE
static double dgeqp3(long N) {
	Eigen::ColPivHouseholderQR<MatrixXd> qr = A.colPivHouseholderQr();
	// flops see http://www.netlib.org/lapack/lawnspdf/lawn41.pdf page 121
	return N * N * N - (2 / 3) * N * N * N + N * N + N * N + (14 / 3) * N;
}

EIGEN_DONT_INLINE
static double dgemv(long N) {
	C = A * b;
	return 2 * N * N - N;
}

EIGEN_DONT_INLINE
static double dtrsm(long N) {
	C = Aqr.solve(B);
	return N * N * N;
}

EIGEN_DONT_INLINE
static double dpotrf(long N) {
	Eigen::LLT<MatrixXd> lltOfA(A);
	L = lltOfA.matrixL();
	return N * N * N / 3.0 + N * N / 2.0 + N / 6.0;
}

EIGEN_DONT_INLINE
static double dgesvd(long N) {
	Eigen::JacobiSVD<MatrixXd> svd(A, Eigen::ComputeThinU | Eigen::ComputeThinV);
	return 22 * N * N * N;
}

int main(int argc, char** argv) {
#if !defined(NDEBUG) || defined(DEBUG)
	fprintf(stderr, "Warning: you are running in debug mode - assertions are enabled. \n");
#endif

	try {
#if defined(EIGEN_USE_MAGMA_ALL)
		MAGMA_INIT();
#endif
		// program arguments
		string function;
		string range;
		int warm_ups, num_runs;

		po::options_description desc("Benchmark main options");
		desc.add_options()("help", "produce help message")
				("warm-up-runs", po::value<int>(&warm_ups)->default_value(1), "warm up runs e.g. 1")
				("num-runs", po::value<int>(&num_runs)->default_value(10), "number of runs e.g. 10")
				("function", po::value < string > (&function)->default_value("dgemm"), "Function to test e.g. dgemm, dgeqp3")
				("range", po::value < string > (&range)->default_value("1024:10240:1024"), "N range i.e. start:stop:step");

		po::variables_map vm;
		po::store(po::parse_command_line(argc, argv, desc), vm);
		po::notify(vm);

		if (vm.count("help")) {
			cout << desc << "\n";
			return EXIT_FAILURE;

		} else {
			string temp = range;
			boost::tokenizer<> tok(temp);
			vector<long> range_values;
			for (boost::tokenizer<>::iterator current = tok.begin(); current != tok.end();
					++current) {
				range_values.push_back(boost::lexical_cast<long>(*current));
			}

			if (range_values.size() != 3) {
				throw "Illegal range input: '" + range + "'";
			}

			workload_type workload;
			if (function == "dgemm") {
				workload = dgemm;
			} else if (function == "dgeqp3") {
				workload = dgeqp3;
			} else if (function == "dgemv") {
				workload = dgemv;
			} else if (function == "dtrsm") {
				workload = dtrsm;
			} else if (function == "dpotrf") {
				workload = dpotrf;
			} else if (function == "dgesvd") {
				workload = dgesvd;
			} else {
				throw "Sorry, the function '" + function + "' is not yet implemented.";
			}

			for (long N = range_values[0]; N <= range_values[1]; N += range_values[2]) {
				// prepare the input data
				A = MatrixXd::Random(N, N);
				B = MatrixXd::Random(N, N);
				b = VectorXd::Random(N);

				// function-specific input data
				if (function == "dtrsm") {
					Aqr = A.colPivHouseholderQr();
				} else if (function == "dpotrf") {
					// make sure A is SDP
					A = A.adjoint() * A;
				}

				real_time_acc = bench_accumulator();
				gflops_acc = bench_accumulator();

				// run the benchmark
				run_benchmark(N, warm_ups, num_runs, workload);

				fprintf(stdout, "%d\t%e\t%e\n", N, mean(real_time_acc), mean(gflops_acc));
				fflush (stdout);
				fprintf(stderr, "%d,%e,%e\n", N, mean(real_time_acc), mean(gflops_acc));
				fflush (stderr);
			}
		}

#if defined(EIGEN_USE_MAGMA_ALL)
		MAGMA_FINALIZE();
#endif
	} catch (std::exception& e) {
		cerr << "Exception: " << e.what() << "\n";
		return EXIT_FAILURE;
	} catch (string& e) {
		cerr << "Exception: " << e << "\n";
		return EXIT_FAILURE;
	} catch (...) {
		cerr << "Exception of unknown type!\n";
		return EXIT_FAILURE;
	}

	return EXIT_SUCCESS;
}
