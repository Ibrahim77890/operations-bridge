chmod +x agent.sh
./agent.sh help
./agent.sh health host
./agent.sh inventory host
./agent.sh something host (failure)
./agent.sh health something
./agent.sh health host | jq . (For json pretty print on terminal)
