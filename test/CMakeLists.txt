# create testrun dir
file(MAKE_DIRECTORY ${PROJECT_BINARY_DIR}/test/testrun)

# test for python coding norms
add_test(NAME test_rdasapp_check_python_norms
         COMMAND pycodestyle -v --config ./.pycodestyle ./ush ./test
         WORKING_DIRECTORY ${PROJECT_SOURCE_DIR})

add_test(NAME test_rdasapp_gen_3dvar_yaml
         COMMAND python3 ${PROJECT_SOURCE_DIR}/test/test_gen_3dvar_yaml.py --input ${PROJECT_SOURCE_DIR}/parm/atm/variational/3dvar_dripcg.yaml --output ${PROJECT_BINARY_DIR}/test/testrun/3dvar_example.yaml
         WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/test/testrun)
