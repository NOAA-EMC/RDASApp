# Function to add key-value pairs to the dictionary
function(add_to_dictionary dict key value)
    # Check if the key already exists
    foreach(entry IN LISTS ${dict})
        string(FIND "${entry}" "=" EQUAL_POS)
        if(EQUAL_POS GREATER -1)
            string(SUBSTRING "${entry}" 0 ${EQUAL_POS} ENTRY_KEY)
            if(ENTRY_KEY STREQUAL ${key})
                # Key exists, check the value
                math(EXPR VALUE_START "${EQUAL_POS} + 1")
                string(SUBSTRING "${entry}" ${VALUE_START} -1 ENTRY_VALUE)
                if(NOT ENTRY_VALUE STREQUAL ${value})
                    message(FATAL_ERROR "Error: Key '${key}' already exists with a different value '${ENTRY_VALUE}'")
                else()
                    return()
                endif()
            endif()
        endif()
    endforeach()

    # Key does not exist, add the new entry
    set(entry "${key}=${value}")
    list(APPEND ${dict} "${entry}")
    set(${dict} "${${dict}}" PARENT_SCOPE)
endfunction()

# Function to get the value by key from the dictionary
function(get_from_dictionary dict key result)
    foreach(entry IN LISTS ${dict})
        string(FIND "${entry}" "=" EQUAL_POS)
        if(EQUAL_POS GREATER -1)
            string(SUBSTRING "${entry}" 0 ${EQUAL_POS} ENTRY_KEY)
            if(ENTRY_KEY STREQUAL ${key})
                math(EXPR VALUE_START "${EQUAL_POS} + 1")
                string(SUBSTRING "${entry}" ${VALUE_START} -1 ENTRY_VALUE)
                set(${result} "${ENTRY_VALUE}" PARENT_SCOPE)
                return()
            endif()
        endif()
    endforeach()
    # If the key is not found, set the result to an empty string or some default value
    set(${result} "" PARENT_SCOPE)
endfunction()
