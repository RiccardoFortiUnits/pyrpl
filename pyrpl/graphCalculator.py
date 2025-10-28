import networkx as nx
from networkx.algorithms.clique import find_cliques

def greedy_clique_partition(graph):
	'''tries to find the smallest set of clique subgraphs that contain all the nodes of the given graph
	clique is a fancy word to say that a graph is completely connected (every of its nodes is connected to all the others)
	the found subgraphs can have node intersections (i.e., a node can be contained in more than one subgraph).
	It's a non-exact algorithm, so you might not get the best set of subgraphs, but at least it's fast
	Example of non-exact result: with graph 
	{	0:	1,2;
		1:	0,3;
		2:	0;
		3:	1}
	the best set is [(0,2),(1,3)], but the algorithm will return [(0,1),(0,2),(3,1)] because of the order of the nodes
	(by just swapping node 1 and 2 you would get the correct set)
	'''
	remaining_nodes = set(graph.nodes())
	partition = []
	initialMaxCliques = None
	while remaining_nodes:
		# Find all maximal cliques in the subgraph of remaining nodes
		subgraph = graph.subgraph(remaining_nodes)
		cliques = list(find_cliques(subgraph))
		if initialMaxCliques is None:
			initialMaxCliques = cliques

		# Choose the largest clique
		largest_clique = set(max(cliques, key=len))
		#now, let's get the initial clique containing this max clique, so that we can also include the nodes already removed from the poll
		largestInitialClique = max([c for c in initialMaxCliques if len(largest_clique.intersection(c)) == len(largest_clique)])
		partition.append(largestInitialClique)

		# Remove nodes of the chosen clique
		remaining_nodes -= set(largest_clique)

	return partition

if __name__ == "__main__":
	# Example graph
	G = nx.Graph()
	edges = [
		(0, 1), (0, 2), (1, 2),
		(3, 4), (4, 5), (3, 5),
		(2,3),(1,4),(3,9),(1,9),(2,9),(0,9),
		(6, 7), (7, 8), (6, 8),
		(8, 9), (6, 9), (7, 9)
	]
	G.add_edges_from(edges)

	# Run greedy partition
	partition = greedy_clique_partition(G)

	# Output result
	print("Number of cliques (greedy):", len(partition))
	print("Clique partitions:", partition)