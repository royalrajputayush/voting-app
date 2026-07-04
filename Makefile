.PHONY: demo clean

demo:
	@chmod +x bootstrap.sh
	@./bootstrap.sh

clean:
	@kind delete cluster --name voting-app-cluster
